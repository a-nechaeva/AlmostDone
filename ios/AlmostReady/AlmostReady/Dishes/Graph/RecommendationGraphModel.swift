import Foundation
import Observation

struct RecommendationGraphSnapshot: Equatable {
    let id: String
    let requestID: UUID
    let stateVersion: Int
    let catalogVersion: String
    let servings: Int

    init(visiblePage page: RecommendationPage) {
        id = page.snapshotID
        requestID = page.requestID
        stateVersion = page.stateVersion
        catalogVersion = page.catalogVersion
        servings = page.servings
    }

    func matches(_ graph: RecommendationGraph) -> Bool {
        graph.snapshotID == id && graph.requestID == requestID && graph.stateVersion == stateVersion
            && graph.catalogVersion == catalogVersion && graph.servings == servings && graph.visibility == .visible
    }
}

@MainActor
final class RecommendationGraphRepository {
    let session: SessionStore
    let account: AccountSession
    private var retryAfter: ContinuousClock.Instant?

    init(session: SessionStore, account: AccountSession) {
        self.session = session
        self.account = account
    }

    var isCurrent: Bool { session.isCurrent(account) }

    func canUse(_ snapshot: RecommendationGraphSnapshot) -> Bool {
        isCurrent && snapshot.stateVersion >= (session.revision?.stateVersion ?? 0)
    }

    func load(_ snapshot: RecommendationGraphSnapshot) async throws -> RecommendationGraphContent {
        while let retryAfter, retryAfter > .now {
            try await Task.sleep(until: retryAfter, clock: .continuous)
        }
        let response: APIResponse<RecommendationGraph>
        do {
            response = try await session.json(
                RecommendationGraph.self,
                for: APIRequest(path: ["recommendations", snapshot.id, "graph"]),
                account: account
            )
        } catch let error as APIClientError {
            if let seconds = error.metadata?.retryAfter.flatMap(Int.init), seconds > 0 {
                let deadline = ContinuousClock.now + .seconds(seconds)
                retryAfter = max(retryAfter ?? deadline, deadline)
            }
            throw error
        }
        guard snapshot.matches(response.value) else { throw APIClientError.invalidResponse(response.metadata) }
        return try RecommendationGraphContent(response: response)
    }
}

@MainActor
@Observable
final class RecommendationGraphModel {
    enum Phase {
        case loading
        case loaded(RecommendationGraphContent)
        case failed
        case refreshSnapshot
    }

    private let repository: RecommendationGraphRepository
    private var activeSnapshot: RecommendationGraphSnapshot?
    private var activeLoad: UUID?
    private var state = Phase.loading

    init(repository: RecommendationGraphRepository) {
        self.repository = repository
    }

    func phase(for snapshot: RecommendationGraphSnapshot) -> Phase {
        guard activeSnapshot == snapshot, repository.canUse(snapshot) else { return .loading }
        return state
    }

    func loadIfNeeded(for snapshot: RecommendationGraphSnapshot) async {
        guard case .loading = phase(for: snapshot) else { return }
        await load(snapshot)
    }

    func retry(for snapshot: RecommendationGraphSnapshot) async {
        guard case .failed = phase(for: snapshot) else { return }
        await load(snapshot)
    }

    func reset() {
        activeLoad = nil
        activeSnapshot = nil
        state = .loading
    }

    private func load(_ snapshot: RecommendationGraphSnapshot) async {
        guard !Task.isCancelled, repository.canUse(snapshot) else { return }
        let loadID = UUID()
        activeLoad = loadID
        activeSnapshot = snapshot
        state = .loading

        do {
            let content = try await repository.load(snapshot)
            guard canPublish(snapshot, loadID: loadID) else { return }
            state = .loaded(content)
        } catch {
            guard canPublish(snapshot, loadID: loadID) else { return }
            if case APIClientError.server(let error, let metadata) = error, metadata.statusCode == 409,
                error.code == "snapshot_expired" || error.code == "context_changed"
            {
                state = .refreshSnapshot
            } else {
                state = .failed
            }
        }
    }

    private func canPublish(_ snapshot: RecommendationGraphSnapshot, loadID: UUID) -> Bool {
        !Task.isCancelled && activeLoad == loadID && repository.canUse(snapshot)
    }
}
