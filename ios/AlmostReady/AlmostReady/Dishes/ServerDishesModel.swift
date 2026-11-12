import Foundation
import Observation

struct DishesSnapshot {
    enum Group: Hashable, Comparable {
        case ready
        case missing(Int)
        case unknown
    }

    let firstPage: RecommendationPage
    let excludedAllergenIDs: [String]
    private(set) var items: [RecommendationCard]
    private(set) var nextCursor: String?

    init(page: RecommendationPage, excludedAllergenIDs: [String]) {
        firstPage = page
        self.excludedAllergenIDs = excludedAllergenIDs
        items = page.items
        nextCursor = page.page.nextCursor
    }

    var groups: [Group: [RecommendationCard]] {
        Dictionary(grouping: items) { card in
            switch card.availability.status {
            case .ready: .ready
            case .missing: .missing(card.availability.missingCount)
            case .unknown: .unknown
            }
        }
    }

    mutating func append(_ page: RecommendationPage) {
        items += page.items
        nextCursor = page.page.nextCursor
    }

    func recipeRequest(for card: RecommendationCard) -> RecipeRequest {
        RecipeRequest(id: card.id, servings: firstPage.servings, excludedAllergenIDs: excludedAllergenIDs)
    }
}

@MainActor
@Observable
final class ServerDishesModel {
    nonisolated struct Context: Equatable, Sendable {
        let query: String
        let filter: DishesFilter
        let stateVersion: Int?
    }

    enum Phase {
        case loading
        case loaded(DishesSnapshot)
        case failed
    }

    var query = ""
    var filter = DishesFilter.all
    private(set) var isLoadingMore = false
    private(set) var pageLoadFailed = false

    let repository: RecommendationsRepository
    private let servings: Int
    private let excludedAllergenIDs: [String]
    private var activeContext: Context?
    private var activeRequestID: UUID?
    private var state = Phase.loading
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?

    init(repository: RecommendationsRepository, servings: Int = 2, excludedAllergenIDs: [String] = []) {
        self.repository = repository
        self.servings = servings
        self.excludedAllergenIDs = excludedAllergenIDs
    }

    nonisolated deinit {}

    var context: Context {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Context(
            query: String(term.unicodeScalars.prefix(200)), filter: filter,
            stateVersion: repository.session.revision?.stateVersion
        )
    }

    var phase: Phase {
        activeContext == context && repository.session.isCurrent(repository.account) ? state : .loading
    }

    func loadIfNeeded(for context: Context) async {
        guard case .loading = phase else { return }
        await startSnapshot(for: context)
    }

    func retry() async {
        guard case .failed = phase else { return }
        await startSnapshot(for: context)
    }

    func refreshSnapshot(requestID: UUID) async {
        guard case .loaded(let snapshot) = phase, snapshot.firstPage.requestID == requestID else { return }
        await startSnapshot(for: context)
    }

    func loadMore() async {
        guard !Task.isCancelled, !isLoadingMore, case .loaded(var snapshot) = phase,
            let cursor = snapshot.nextCursor
        else { return }

        let context = context
        let first = snapshot.firstPage
        isLoadingMore = true
        pageLoadFailed = false
        defer {
            if activeRequestID == first.requestID { isLoadingMore = false }
        }
        do {
            let response = try await repository.page(snapshotID: first.snapshotID, cursor: cursor)
            guard canPublish(for: context, requestID: first.requestID) else { return }

            let page = response.value
            try validate(response, requestID: first.requestID, minimumVersion: first.stateVersion)
            guard page.snapshotID == first.snapshotID, page.stateVersion == first.stateVersion,
                page.catalogVersion == first.catalogVersion, page.page.nextCursor != cursor
            else { throw APIClientError.invalidResponse(response.metadata) }

            snapshot.append(page)
            state = .loaded(snapshot)
        } catch {
            guard canPublish(for: context, requestID: first.requestID) else { return }
            if case APIClientError.server(let payload, let metadata) = error, metadata.statusCode == 409,
                payload.code == "snapshot_expired" || payload.code == "context_changed"
            {
                await startSnapshot(for: context)
            } else {
                pageLoadFailed = true
            }
        }
    }

    private func startSnapshot(for context: Context) async {
        guard !Task.isCancelled, context == self.context, repository.session.isCurrent(repository.account) else {
            return
        }

        // Keep an in-flight snapshot when the tab disappears and reappears with the same context.
        if activeContext == context, snapshotTask != nil { return }
        snapshotTask?.cancel()
        let requestID = UUID()
        activeRequestID = requestID
        activeContext = context
        state = .loading
        isLoadingMore = false
        pageLoadFailed = false

        let request = RecommendationRequest(
            requestID: requestID, servings: servings,
            filters: .init(query: context.query, mode: context.filter, excludedAllergenIDs: excludedAllergenIDs)
        )
        let task = Task {
            defer {
                if activeRequestID == requestID { snapshotTask = nil }
            }
            await fetchSnapshot(request, for: context)
        }
        snapshotTask = task
        await task.value
    }

    private func fetchSnapshot(_ request: RecommendationRequest, for context: Context) async {
        let requestID = request.requestID
        do {
            let response = try await repository.create(request)
            guard canPublish(for: context, requestID: requestID) else { return }
            try validate(response, requestID: requestID, minimumVersion: context.stateVersion ?? 0)
            state = .loaded(
                DishesSnapshot(page: response.value, excludedAllergenIDs: request.filters.excludedAllergenIDs))
        } catch {
            guard canPublish(for: context, requestID: requestID) else { return }
            state = .failed
        }
    }

    private func canPublish(for context: Context, requestID: UUID) -> Bool {
        !Task.isCancelled && context == self.context && requestID == activeRequestID
            && repository.session.isCurrent(repository.account)
    }

    private func validate(
        _ response: APIResponse<RecommendationPage>, requestID: UUID, minimumVersion: Int
    ) throws {
        let page = response.value
        guard page.requestID == requestID, !page.snapshotID.isEmpty, !page.catalogVersion.isEmpty,
            page.stateVersion >= minimumVersion, page.visibility == "visible",
            page.servings == servings, page.items.allSatisfy({ $0.servings == page.servings }),
            page.page.hasMore == (page.page.nextCursor != nil)
        else { throw APIClientError.invalidResponse(response.metadata) }

        if let etag = response.metadata.etag {
            _ = try AccountRevision(etag: etag, stateVersion: page.stateVersion)
        }
    }
}
