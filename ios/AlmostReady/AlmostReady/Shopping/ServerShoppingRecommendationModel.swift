import Foundation
import Observation

@Observable
final class ServerShoppingRecommendationModel {
    enum RecommendationState {
        case idle
        case loading
        case invalidBudget(ShoppingBudgetError)
        case unavailable
        case result(ShoppingRecommendation)
    }

    private let repository: ShoppingRepository
    private let shopping: ServerShoppingModel
    private var recommendationID: UUID?
    private var recommendationRetryAfter: ContinuousClock.Instant?

    init(repository: ShoppingRepository, shopping: ServerShoppingModel) {
        self.repository = repository
        self.shopping = shopping
    }

    nonisolated deinit {}

    var revision: AccountRevision? { repository.revision }
    var storageUnavailable: Bool { shopping.storageUnavailable }

    var budgetInput = "500" {
        didSet { if budgetInput != oldValue { discardRecommendation() } }
    }

    var servings = 2 {
        didSet { if servings != oldValue { discardRecommendation() } }
    }

    var filters = ShoppingFilters() {
        didSet { if filters != oldValue { discardRecommendation() } }
    }

    private(set) var recommendation: RecommendationState = .idle
    func discardRecommendation() {
        recommendationID = nil
        recommendation = .idle
    }

    func isCurrentRecommendation(_ id: UUID) -> Bool {
        repository.isCurrent && recommendationID == id
    }

    @discardableResult
    func loadRecommendation(_ kind: ShoppingRecommendationKind) async -> UUID? {
        guard repository.isCurrent else { return nil }
        if case .loading = recommendation { return nil }

        let id = UUID()
        recommendationID = id
        let budget: Int
        switch shoppingBudgetAmount(budgetInput) {
        case .success(let amount) where amount * 100 <= Decimal(Int.max):
            budget = NSDecimalNumber(decimal: amount * 100).intValue
        case .success:
            recommendation = .invalidBudget(.invalid)
            return id
        case .failure(let error):
            recommendation = .invalidBudget(error)
            return id
        }

        let request = ShoppingPurchaseRequest(
            requestID: id, servings: servings, filters: filters, budget: ShoppingMoney(minorUnits: budget)
        )
        let startingRevision = revision
        recommendation = .loading
        defer {
            if recommendationID == id, case .loading = recommendation { discardRecommendation() }
        }

        do {
            if let deadline = recommendationRetryAfter, deadline > .now {
                try await Task.sleep(until: deadline, clock: .continuous)
            }
            guard isCurrentRequest(id, startingRevision: startingRevision) else { return nil }
            let result = try await repository.recommendations(kind, request: request)
            guard isCurrentRequest(id, startingRevision: startingRevision),
                shopping.isFresh(result.revision)
            else { return nil }
            repository.session.noteShoppingRevision(result.revision, for: repository.account)
            recommendation = .result(result)
        } catch {
            guard isCurrentRequest(id, startingRevision: startingRevision) else { return nil }
            if let deadline = retryDeadline(error) {
                recommendationRetryAfter = max(recommendationRetryAfter ?? deadline, deadline)
            }
            recommendation = .unavailable
        }
        return id
    }

    private func isCurrentRequest(_ id: UUID, startingRevision: AccountRevision?) -> Bool {
        isCurrentRecommendation(id) && !Task.isCancelled && revision == startingRevision
    }

    func addition(for suggestion: ShoppingSuggestion) -> ServerShoppingModel.SuggestionAddition {
        guard case .result(let result) = recommendation else { return .needsFreshSnapshot }
        return shopping.addition(for: suggestion.items, basedOn: result.revision)
    }

    func contains(_ package: ShoppingPackage) -> Bool {
        shopping.contains(package)
    }

    @discardableResult
    func add(_ suggestion: ShoppingSuggestion, undoable: Bool = false) -> Bool {
        guard case .result(let result) = recommendation,
            let current = result.suggestions.first(where: { $0.id == suggestion.id })
        else { return false }
        return shopping.add(current.items, basedOn: result.revision, undoable: undoable) == .added
    }

    private func retryDeadline(_ error: Error) -> ContinuousClock.Instant? {
        guard let value = (error as? APIClientError)?.metadata?.retryAfter,
            let seconds = Int(value), seconds > 0
        else { return nil }
        return ContinuousClock.now.advanced(by: .seconds(seconds))
    }
}
