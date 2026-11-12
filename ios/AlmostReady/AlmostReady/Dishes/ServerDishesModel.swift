import Foundation
import Observation

struct DishesSnapshot {
    enum Group: Hashable, Comparable {
        case ready
        case missing(Int)
        case unknown
    }

    let firstPage: RecommendationPage
    let context: ServerDishesModel.Context
    private(set) var items: [RecommendationCard]
    private(set) var nextCursor: String?

    init(page: RecommendationPage, context: ServerDishesModel.Context) {
        firstPage = page
        var context = context
        context.stateVersion = page.stateVersion
        self.context = context
        items = page.items
        nextCursor = page.page.nextCursor
    }

    var excludedAllergenIDs: [String] { context.advancedFilters.excludedAllergenIDs.sorted() }

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
    nonisolated struct Context: Hashable, Sendable {
        var query = ""
        var filter = DishesFilter.all
        var advancedFilters = DishesAdvancedFilters()
        var servings = 2
        var stateVersion: Int?

        var requestFilters: RecommendationRequest.Filters {
            .init(
                query: query, mode: filter,
                maxMinutes: advancedFilters.maxMinutes, maxKcalPerServing: advancedFilters.maxKcalPerServing,
                equipment: advancedFilters.equipmentIDs,
                excludedAllergenIDs: advancedFilters.excludedAllergenIDs.sorted()
            )
        }
    }

    enum Phase {
        case loading
        case loaded(DishesSnapshot)
        case failed
    }

    var query: String
    var filter: DishesFilter
    private(set) var advancedFilters: DishesAdvancedFilters
    private(set) var isLoadingMore = false
    private(set) var pageLoadFailed = false

    let repository: RecommendationsRepository
    let visibility: RecommendationRequest.Visibility
    private let servings: Int
    private let minimumStateVersion: Int?
    private var activeContext: Context?
    private var activeRequestID: UUID?
    private var state = Phase.loading
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?

    init(
        repository: RecommendationsRepository, initialContext: Context = .init(),
        visibility: RecommendationRequest.Visibility = .visible
    ) {
        self.repository = repository
        self.visibility = visibility
        query = initialContext.query
        filter = initialContext.filter
        advancedFilters = initialContext.advancedFilters
        servings = initialContext.servings
        minimumStateVersion = initialContext.stateVersion
    }

    nonisolated deinit {}

    var context: Context {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let revision = repository.session.revision?.stateVersion
        let minimum = minimumStateVersion.map { max($0, revision ?? $0) }
        return Context(
            query: String(term.unicodeScalars.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines),
            filter: filter,
            advancedFilters: advancedFilters, servings: servings,
            stateVersion: minimum ?? revision
        )
    }

    var phase: Phase {
        activeContext == context && repository.session.isCurrent(repository.account) ? state : .loading
    }

    func apply(_ filters: DishesAdvancedFilters) {
        guard advancedFilters != filters else { return }
        advancedFilters = filters
        activeContext = nil
        activeRequestID = nil
        snapshotTask?.cancel()
        snapshotTask = nil
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
            requestID: requestID, servings: context.servings, filters: context.requestFilters, visibility: visibility
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
            state = .loaded(DishesSnapshot(page: response.value, context: context))
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
            page.stateVersion >= minimumVersion, page.visibility == visibility,
            page.servings == servings,
            page.items.allSatisfy({
                $0.servings == page.servings && ($0.suitability.status == .hidden) == (visibility == .hidden)
            }),
            page.page.hasMore == (page.page.nextCursor != nil)
        else { throw APIClientError.invalidResponse(response.metadata) }

        if let etag = response.metadata.etag {
            _ = try AccountRevision(etag: etag, stateVersion: page.stateVersion)
        }
    }
}
