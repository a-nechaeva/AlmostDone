import Foundation
import Observation

@Observable
final class IngredientSearchModel {
    enum Phase {
        case idle
        case loading
        case results([CatalogIngredient])
        case failed
    }

    var query = "" {
        didSet {
            if query != oldValue { restart() }
        }
    }

    private(set) var phase = Phase.idle
    private(set) var requestID = UUID()
    private(set) var nextCursor: String?
    private(set) var isLoadingMore = false
    private(set) var pageLoadFailed = false

    private let repository: ProductsRepository

    init(repository: ProductsRepository) {
        self.repository = repository
    }

    func restart() {
        requestID = UUID()
        nextCursor = nil
        isLoadingMore = false
        pageLoadFailed = false
        phase = term.isEmpty ? .idle : .loading
    }

    func search(request id: UUID) async {
        let query = term
        guard id == requestID, !query.isEmpty else { return }
        phase = .loading
        do {
            let response = try await repository.search(query)
            guard canPublish(id) else { return }
            nextCursor = response.page.nextCursor
            phase = .results(response.items)
        } catch {
            guard canPublish(id) else { return }
            phase = .failed
        }
    }

    func loadMore() async {
        guard case .results(let items) = phase, let cursor = nextCursor, !isLoadingMore else { return }
        let id = requestID
        isLoadingMore = true
        pageLoadFailed = false
        defer {
            if id == requestID { isLoadingMore = false }
        }
        do {
            let response = try await repository.search(term, cursor: cursor)
            guard canPublish(id) else { return }
            nextCursor = response.page.nextCursor
            phase = .results(items + response.items)
        } catch {
            guard canPublish(id) else { return }
            if case APIClientError.server(let payload, _) = error, payload.code == "context_changed" {
                restart()
            } else {
                pageLoadFailed = true
            }
        }
    }

    private var term: String {
        String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
    }

    private func canPublish(_ id: UUID) -> Bool {
        id == requestID && !Task.isCancelled && repository.isCurrent
    }
}
