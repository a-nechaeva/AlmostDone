import Foundation
import Observation

struct RecommendationGraphSnapshot: Equatable {
    let id: String
    let requestID: UUID
    let stateVersion: Int
    let catalogVersion: String
    let servings: Int

    let filters: RecommendationRequest.Filters

    init(_ snapshot: DishesSnapshot) {
        let page = snapshot.firstPage
        id = page.snapshotID
        requestID = page.requestID
        stateVersion = page.stateVersion
        catalogVersion = page.catalogVersion
        servings = page.servings
        filters = snapshot.context.requestFilters
    }

    func matches(_ graph: RecommendationGraph) -> Bool {
        graph.snapshotID == id && graph.requestID == requestID && graph.stateVersion == stateVersion
            && graph.catalogVersion == catalogVersion && graph.servings == servings && graph.visibility == .visible
            && graph.filters.query == filters.query && graph.filters.mode == filters.mode
            && graph.filters.maxMinutes == filters.maxMinutes
            && Set(graph.filters.equipment) == Set(filters.equipment)
            && Set(graph.filters.excludedAllergenIDs) == Set(filters.excludedAllergenIDs)
            && wireKcal(graph.filters.maxKcalPerServing) == wireKcal(filters.maxKcalPerServing)
    }

    private func wireKcal(_ amount: Decimal?) -> Double? {
        // The server parses JSON numbers as binary floating point before echoing the filters.
        amount.flatMap { Double($0.description) }
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

        var expiration: Date? {
            if case .loaded(let content) = self { content.expiresAt } else { nil }
        }
    }

    private let repository: RecommendationsRepository
    private var activeSnapshot: RecommendationGraphSnapshot?
    private var activeLoad: UUID?
    private var state = Phase.loading
    private(set) var retryAttempt = 0

    init(repository: RecommendationsRepository) {
        self.repository = repository
    }

    nonisolated deinit {}

    func phase(for snapshot: RecommendationGraphSnapshot) -> Phase {
        guard repository.session.isCurrent(repository.account),
            snapshot.stateVersion >= (repository.session.revision?.stateVersion ?? 0)
        else { return .loading }
        if snapshot.stateVersion < (repository.session.shoppingRevision?.stateVersion ?? 0) {
            return .refreshSnapshot
        }
        guard activeSnapshot == snapshot else { return .loading }
        if case .loaded(let content) = state, content.expiresAt <= .now { return .refreshSnapshot }
        return state
    }

    func loadIfNeeded(for snapshot: RecommendationGraphSnapshot) async {
        guard case .loading = phase(for: snapshot) else { return }
        await load(snapshot)
    }

    func requestRetry(for snapshot: RecommendationGraphSnapshot) {
        guard case .failed = phase(for: snapshot) else { return }
        state = .loading
        retryAttempt += 1
    }

    func reset() {
        activeLoad = nil
        activeSnapshot = nil
        state = .loading
    }

    func loadIfNeeded(for snapshot: RecommendationGraphSnapshot, retryAttempt: Int) async {
        guard retryAttempt == self.retryAttempt else { return }
        await loadIfNeeded(for: snapshot)
    }

    private func load(_ snapshot: RecommendationGraphSnapshot) async {
        guard !Task.isCancelled, canUse(snapshot) else { return }
        let loadID = UUID()
        activeLoad = loadID
        activeSnapshot = snapshot
        state = .loading

        do {
            let response = try await repository.graph(snapshotID: snapshot.id)
            guard canPublish(snapshot, loadID: loadID) else { return }
            guard snapshot.matches(response.value) else { throw APIClientError.invalidResponse(response.metadata) }
            let content = try RecommendationGraphContent(response: response)
            state = .loaded(content)
        } catch {
            guard canPublish(snapshot, loadID: loadID) else { return }
            if case APIClientError.server(let error, let metadata) = error,
                (metadata.statusCode == 404 && error.code == "not_found")
                    || (metadata.statusCode == 409
                        && (error.code == "snapshot_expired" || error.code == "context_changed"))
            {
                state = .refreshSnapshot
            } else {
                state = .failed
            }
        }
    }

    func observeExpiration(for snapshot: RecommendationGraphSnapshot, at expiry: Date) async {
        let remaining = expiry.timeIntervalSinceNow
        if remaining > 0 {
            do {
                try await Task.sleep(for: .seconds(remaining))
            } catch {
                return
            }
        }
        guard !Task.isCancelled, activeSnapshot == snapshot, case .loaded(let content) = state,
            content.expiresAt == expiry, expiry <= .now
        else { return }
        state = .refreshSnapshot
    }

    private func canUse(_ snapshot: RecommendationGraphSnapshot) -> Bool {
        repository.session.isCurrent(repository.account)
            && snapshot.stateVersion >= (repository.session.revision?.stateVersion ?? 0)
            && snapshot.stateVersion >= (repository.session.shoppingRevision?.stateVersion ?? 0)
    }

    private func canPublish(_ snapshot: RecommendationGraphSnapshot, loadID: UUID) -> Bool {
        !Task.isCancelled && activeLoad == loadID && canUse(snapshot)
    }
}
