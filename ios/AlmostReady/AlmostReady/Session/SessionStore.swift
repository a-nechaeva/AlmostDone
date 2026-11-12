import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    enum Notice: Equatable {
        case signInFailed
        case signInRequired
        case storageUnavailable
        case revocationUnconfirmed
    }

    enum Phase: Equatable {
        case starting
        case restoring
        case restoreFailed
        case signedOut(Notice?)
        case signingIn
        case signedIn(AccountSession)
        case signingOut
    }

    private(set) var phase: Phase = .starting
    private(set) var revision: AccountRevision?
    private(set) var shoppingRevision: AccountRevision?
    @ObservationIgnored private weak var sharedShopping: ServerShoppingModel?
    @ObservationIgnored private(set) var ingredientNutritionCatalog = IngredientNutritionCatalog()

    private let client: APIClient
    private let yandex: any YandexAuthorizing
    private let storage: any SessionStorage
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var tokens: SessionTokens?
    @ObservationIgnored private var refreshTask: Task<SessionTokens, Error>?

    init(client: APIClient, yandex: any YandexAuthorizing, storage: any SessionStorage) {
        self.client = client
        self.yandex = yandex
        self.storage = storage
    }

    var account: AccountSession? {
        guard case .signedIn(let account) = phase else { return nil }
        return account
    }

    var serverIdentity: String { client.serverIdentity }

    func shoppingModel(for account: AccountSession) -> ServerShoppingModel {
        if let sharedShopping, isCurrent(account) { return sharedShopping }
        let model = ServerShoppingModel(
            repository: ShoppingRepository(session: self, account: account),
            storage: ShoppingStorage(serverIdentity: serverIdentity, userID: account.userID)
        )
        if isCurrent(account) { sharedShopping = model }
        return model
    }

    func noteShoppingRevision(_ updated: AccountRevision, for account: AccountSession) {
        guard isCurrent(account), updated.stateVersion > (shoppingRevision?.stateVersion ?? -1) else { return }
        shoppingRevision = updated
    }

    func restore() async {
        guard phase == .starting || phase == .restoreFailed else { return }
        phase = .restoring
        let id = generation
        do {
            switch try storage.load() {
            case nil:
                tokens = nil
                phase = .signedOut(nil)
            case .refreshing:
                try expire()
            case .active(let restored):
                tokens = restored
                let revision = try await verifyAccount(id: id, userID: restored.userID)
                try requireCurrent(id)
                self.revision = revision
                phase = .signedIn(AccountSession(id: id, userID: restored.userID))
            }
        } catch {
            if generation == id { phase = .restoreFailed }
        }
    }

    func signIn() async {
        guard case .signedOut = phase else { return }
        phase = .signingIn
        let id = generation
        do {
            // A failed local cleanup must be resolved before accepting another account.
            try removeStoredSession()
            let oauthToken = try await yandex.oauthToken()
            try requireCurrent(id)
            guard !oauthToken.isEmpty else { throw SessionError.invalidServerSession }
            let response = try await client.json(
                ServerSessionResponse.self,
                for: APIRequest(
                    path: ["auth", "yandex"], method: .post,
                    jsonBody: YandexExchange(oauthToken: oauthToken)
                )
            )
            try requireCurrent(id)
            guard response.metadata.statusCode == 200 else { throw SessionError.invalidServerSession }
            let issued = try response.value.tokens()
            let state = try await client.json(
                AccountState.self,
                for: APIRequest(path: ["me", "state"], headers: .init(bearerToken: issued.accessToken))
            )
            try requireCurrent(id)
            let revision = try accountRevision(state, userID: issued.userID)
            try save(.active(issued))
            tokens = issued
            self.revision = revision
            phase = .signedIn(AccountSession(id: id, userID: issued.userID))
        } catch {
            guard generation == id else { return }
            switch error {
            case YandexAuthorizationError.cancelled:
                phase = .signedOut(nil)
            case SessionError.storageUnavailable:
                phase = .signedOut(.storageUnavailable)
            default:
                phase = .signedOut(.signInFailed)
            }
        }
    }

    @discardableResult
    func signOut() async throws -> LogoutResult {
        guard phase != .signingOut else { return .localOnly }
        let prior = tokens
        let pending = refreshTask
        resetAccount()
        phase = .signingOut

        let removal = Result { try removeStoredSession() }
        // Rotation revokes the old access token. If it was already sent, revoke the new
        // pair's family with its new access token without installing that pair locally.
        let rotated = try? await pending?.value
        let result: LogoutResult
        if let accessToken = (rotated ?? prior)?.accessToken {
            result = await revoke(accessToken)
        } else {
            result = .localOnly
        }

        do {
            try removal.get()
            let confirmed = result == .revoked || result == .localOnly
            phase = .signedOut(confirmed ? nil : .revocationUnconfirmed)
            return result
        } catch {
            phase = .signedOut(.storageUnavailable)
            throw error
        }
    }

    func isCurrent(_ account: AccountSession) -> Bool {
        self.account == account
    }

    func json<Value: Decodable & Sendable>(
        _ type: Value.Type, for request: APIRequest, account: AccountSession
    ) async throws -> APIResponse<Value> {
        try requireAccount(account)
        return try await authorized(request, id: account.id) { try await client.json(type, for: $0) }
    }

    func data(for request: APIRequest, account: AccountSession) async throws -> APIResponse<Data> {
        try requireAccount(account)
        return try await authorized(request, id: account.id) { try await client.data(for: $0) }
    }

    func publicData(path: [String]) async throws -> APIResponse<Data> {
        try await client.data(for: APIRequest(path: path))
    }

    func empty(for request: APIRequest, account: AccountSession) async throws -> APIResponse<Void> {
        try requireAccount(account)
        return try await authorized(request, id: account.id) { try await client.empty(for: $0) }
    }

    @discardableResult
    func reloadRevision(for account: AccountSession) async throws -> AccountRevision {
        try requireAccount(account)
        guard let tokens else { throw SessionError.noSession }
        let updated = try await verifyAccount(id: account.id, userID: tokens.userID)
        try requireAccount(account)
        return advanceRevision(updated)
    }

    func confirmMutation(
        _ metadata: HTTPResponseMetadata, stateVersion: Int? = nil, account: AccountSession
    ) throws {
        try requireAccount(account)
        guard (200..<300).contains(metadata.statusCode) else { throw SessionError.invalidStateRevision }
        advanceRevision(try AccountRevision(etag: metadata.etag, stateVersion: stateVersion))
    }

    private func verifyAccount(id: UUID, userID: String) async throws -> AccountRevision {
        let response = try await authorized(APIRequest(path: ["me", "state"]), id: id) {
            try await client.json(AccountState.self, for: $0)
        }
        return try accountRevision(response, userID: userID)
    }

    private func accountRevision(_ response: APIResponse<AccountState>, userID: String) throws -> AccountRevision {
        guard response.metadata.statusCode == 200, response.value.userID == userID,
            !response.value.catalogVersion.isEmpty
        else { throw SessionError.invalidServerSession }
        return try AccountRevision(etag: response.metadata.etag, stateVersion: response.value.stateVersion)
    }

    @discardableResult
    private func advanceRevision(_ updated: AccountRevision) -> AccountRevision {
        if let revision, revision.stateVersion >= updated.stateVersion { return revision }
        revision = updated
        return updated
    }

    private func authorized<Value>(
        _ request: APIRequest, id: UUID,
        send: (APIRequest) async throws -> APIResponse<Value>
    ) async throws -> APIResponse<Value> {
        let initial: SessionTokens
        if let refreshTask {
            initial = try await waitForRefresh(refreshTask, id: id)
        } else {
            guard let tokens else { throw SessionError.noSession }
            initial = tokens
        }
        var request = request
        request.headers.bearerToken = initial.accessToken
        do {
            return try await sendWhileCurrent(request, id: id, send: send)
        } catch let error as APIClientError where error.metadata?.statusCode == 401 {
            let renewed = try await refresh(after: initial.accessToken, id: id)
            // Only reads are replayed by the session layer. Reconcile failed writes at the screen.
            guard request.method == .get else { throw error }
            request.headers.bearerToken = renewed.accessToken
            do {
                return try await sendWhileCurrent(request, id: id, send: send)
            } catch let error as APIClientError where error.metadata?.statusCode == 401 {
                if tokens?.accessToken == renewed.accessToken, refreshTask == nil {
                    try expire()
                    throw SessionError.signInRequired
                }
                throw error
            }
        }
    }

    private func sendWhileCurrent<Value>(
        _ request: APIRequest, id: UUID,
        send: (APIRequest) async throws -> APIResponse<Value>
    ) async throws -> APIResponse<Value> {
        try requireCurrent(id)
        let result: Result<APIResponse<Value>, Error>
        do {
            result = .success(try await send(request))
        } catch {
            result = .failure(error)
        }
        try requireCurrent(id)
        return try result.get()
    }

    private func refresh(after rejectedAccess: String, id: UUID) async throws -> SessionTokens {
        try requireCurrent(id)
        if let refreshTask { return try await waitForRefresh(refreshTask, id: id) }
        guard let tokens else { throw SessionError.noSession }
        if tokens.accessToken != rejectedAccess { return tokens }
        if let until = tokens.refreshNotBefore, until > .now {
            throw SessionError.refreshRateLimited(until: until)
        }

        // Persist the in-flight marker before sending the single-use refresh token.
        // A process killed during rotation must never restore and reuse the old pair.
        try save(.refreshing)
        let task = Task { try await rotate(tokens, id: id) }
        refreshTask = task
        return try await waitForRefresh(task, id: id)
    }

    private func waitForRefresh(_ task: Task<SessionTokens, Error>, id: UUID) async throws -> SessionTokens {
        let result = await task.result
        if case .failure(let error as SessionError) = result, error == .signInRequired || error == .storageUnavailable {
            throw error
        }
        try requireCurrent(id)
        return try result.get()
    }

    private func rotate(_ old: SessionTokens, id: UUID) async throws -> SessionTokens {
        try requireCurrent(id)
        defer {
            if generation == id { refreshTask = nil }
        }
        do {
            let response = try await client.json(
                ServerSessionResponse.self,
                for: APIRequest(
                    path: ["auth", "refresh"], method: .post,
                    jsonBody: SessionRefresh(refreshToken: old.refreshToken)
                )
            )
            let next = try response.value.tokens()
            guard response.metadata.statusCode == 200, next.userID == old.userID,
                next.accessToken != old.accessToken, next.refreshToken != old.refreshToken
            else { throw SessionError.invalidServerSession }
            if generation == id {
                try save(.active(next))
                tokens = next
            }
            return next
        } catch APIClientError.server(let payload, let metadata)
            where metadata.statusCode == 429 && payload.code == "rate_limited"
        {
            try requireCurrent(id)
            guard let retryAfter = metadata.retryAfter.flatMap(Int.init), retryAfter > 0 else {
                try expire()
                throw SessionError.signInRequired
            }
            var delayed = old
            delayed.refreshNotBefore = Date.now.addingTimeInterval(TimeInterval(retryAfter))
            do {
                try save(.active(delayed))
                tokens = delayed
            } catch {
                try expire()
                throw SessionError.storageUnavailable
            }
            throw APIClientError.server(payload, metadata)
        } catch {
            guard generation == id else { throw SessionError.sessionChanged }
            try expire()
            if case SessionError.storageUnavailable = error { throw error }
            throw SessionError.signInRequired
        }
    }

    private func revoke(_ accessToken: String) async -> LogoutResult {
        do {
            let response = try await client.empty(
                for: APIRequest(path: ["auth", "logout"], method: .post, headers: .init(bearerToken: accessToken))
            )
            return response.metadata.statusCode == 204 ? .revoked : .revocationUnconfirmed
        } catch let error as APIClientError where error.metadata?.statusCode == 401 {
            return .alreadyUnauthorized
        } catch {
            return .revocationUnconfirmed
        }
    }

    private func requireAccount(_ account: AccountSession) throws {
        try requireCurrent(account.id)
        guard isCurrent(account) else { throw SessionError.noSession }
    }

    private func requireCurrent(_ id: UUID) throws {
        guard generation == id else { throw SessionError.sessionChanged }
    }

    private func expire() throws {
        resetAccount()
        do {
            try removeStoredSession()
            phase = .signedOut(.signInRequired)
        } catch {
            phase = .signedOut(.storageUnavailable)
            throw error
        }
    }

    private func resetAccount() {
        generation = UUID()
        ingredientNutritionCatalog = IngredientNutritionCatalog()
        refreshTask = nil
        tokens = nil
        revision = nil
        shoppingRevision = nil
        sharedShopping = nil
    }

    private func save(_ session: StoredSession) throws {
        do {
            try storage.save(session)
        } catch {
            throw SessionError.storageUnavailable
        }
    }

    private func removeStoredSession() throws {
        do {
            try storage.remove()
        } catch {
            throw SessionError.storageUnavailable
        }
    }
}
