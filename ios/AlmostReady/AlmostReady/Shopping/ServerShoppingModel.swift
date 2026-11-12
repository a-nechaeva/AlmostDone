import Foundation
import Observation

@Observable
final class ServerShoppingModel {
    enum RecommendationState {
        case idle
        case loading
        case invalidBudget(ShoppingBudgetError)
        case unavailable
        case result(ShoppingRecommendation)
    }

    enum SuggestionAddition: Equatable {
        case add
        case update
        case alreadyAdded
        case marked
    }

    enum TransferState: Equatable {
        case idle
        case transferring
        case needsConfirmation
        case revisionUnavailable
        case retry
        case invalidSelection
        case rejected
        case completed
    }

    private struct Row: Identifiable {
        let package: ShoppingPackage
        let revision: AccountRevision
        var isPurchased = false

        var id: String { package.key }

        var item: ShoppingItem {
            ShoppingItem(
                id: id, name: package.name, quantity: package.quantityLabel,
                estimatedPrice: package.totalPrice?.rubles, isPurchased: isPurchased
            )
        }
    }

    private struct Transfer {
        let rowIDs: Set<String>
        let batch: ShoppingPurchasedBatch
        let key = UUID()
        var revision: AccountRevision?
    }

    private let repository: ShoppingRepository
    private var rows: [Row] = []
    private var recommendationID: UUID?
    private var recommendationRetryAfter: ContinuousClock.Instant?
    private var transferRetryAfter: ContinuousClock.Instant?
    private var pendingTransfer: Transfer?

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
    private(set) var transferState: TransferState = .idle

    init(repository: ShoppingRepository) {
        self.repository = repository
    }

    // Match the lifecycle workaround used by the other SwiftUI feature models on iOS 26.2.
    nonisolated deinit {}

    var revision: AccountRevision? { repository.revision }
    var items: [ShoppingItem] { rows.map(\.item) }
    var markedCount: Int { rows.filter(\.isPurchased).count }
    var isSelectionLocked: Bool { pendingTransfer != nil }

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
                result.revision.stateVersion >= (revision?.stateVersion ?? 0)
            else { return nil }
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

    func addition(for suggestion: ShoppingSuggestion) -> SuggestionAddition {
        let changes = neededPackages(for: suggestion)
        if changes.isEmpty { return .alreadyAdded }
        let existing = rows.filter { row in changes.contains { $0.id == row.id } }
        if existing.contains(where: \.isPurchased) { return .marked }
        return existing.isEmpty ? .add : .update
    }

    @discardableResult
    func add(_ suggestion: ShoppingSuggestion) -> Bool {
        guard repository.isCurrent, !isSelectionLocked, case .result(let result) = recommendation,
            result.revision.stateVersion >= (revision?.stateVersion ?? 0),
            let current = result.suggestions.first(where: { $0.id == suggestion.id })
        else { return false }

        let changes = neededPackages(for: current)
        guard !changes.isEmpty, addition(for: current) != .marked else { return false }
        for item in changes {
            let row = Row(package: item, revision: result.revision)
            if let index = rows.firstIndex(where: { $0.id == item.id }) {
                rows[index] = row
            } else {
                rows.append(row)
            }
        }
        return true
    }

    private func neededPackages(for suggestion: ShoppingSuggestion) -> [ShoppingPackage] {
        suggestion.items.filter { item in
            guard let existing = rows.first(where: { $0.id == item.id })?.package else { return true }
            return existing.packageQuantity != item.packageQuantity || existing.packageCount < item.packageCount
        }
    }

    func setPurchased(_ isPurchased: Bool, id: String) -> ShoppingItem? {
        guard !isSelectionLocked, let index = rows.firstIndex(where: { $0.id == id }) else { return nil }
        rows[index].isPurchased = isPurchased
        transferState = .idle
        return rows[index].item
    }

    func confirmTransfer() async {
        guard repository.isCurrent, transferState != .transferring else { return }
        guard var transfer = pendingTransfer ?? makeTransfer() else {
            transferState = .invalidSelection
            return
        }

        pendingTransfer = transfer
        transferState = .transferring
        do {
            if let deadline = transferRetryAfter, deadline > .now {
                try await Task.sleep(until: deadline, clock: .continuous)
            }
            if let revision = transfer.revision {
                try await repository.transfer(transfer.batch, basedOn: revision, key: transfer.key)
                guard repository.isCurrent else { return }
                rows.removeAll { transfer.rowIDs.contains($0.id) }
                pendingTransfer = nil
                transferState = .completed
                discardRecommendation()
            } else {
                await refreshRevision(for: transfer)
            }
        } catch {
            guard repository.isCurrent else { return }
            transferRetryAfter = retryDeadline(error)
            let status = (error as? APIClientError)?.metadata?.statusCode
            switch status {
            case 412:
                transfer.revision = nil
                pendingTransfer = transfer
                await refreshRevision(for: transfer)
            case 422:
                pendingTransfer = nil
                transferState = .rejected
            case 409 where isUnitConflict(error):
                pendingTransfer = nil
                transferState = .rejected
            default:
                // A timeout can arrive after commit. Retry the same operation with its original precondition.
                transferState = .retry
            }
        }
    }

    private func refreshRevision(for transfer: Transfer) async {
        do {
            let revision = try await repository.reloadRevision()
            guard repository.isCurrent else { return }
            var refreshed = transfer
            refreshed.revision = revision
            pendingTransfer = refreshed
            transferState = .needsConfirmation
            discardRecommendation()
        } catch {
            guard repository.isCurrent else { return }
            transferRetryAfter = retryDeadline(error)
            transferState = .revisionUnavailable
        }
    }

    func cancelReconciledTransfer() {
        guard transferState == .needsConfirmation || transferState == .revisionUnavailable else { return }
        pendingTransfer = nil
        transferState = .idle
    }

    private func makeTransfer() -> Transfer? {
        let marked = rows.filter(\.isPurchased)
        guard let oldest = marked.min(by: { $0.revision.stateVersion < $1.revision.stateVersion }) else { return nil }

        var quantities: [String: PantryQuantity] = [:]
        for row in marked {
            let package = row.package
            let unit = package.packageQuantity.unit
            let previous = quantities[package.ingredientID]
            guard package.packageCount > 0, package.packageQuantity.value > 0,
                previous == nil || previous?.unit == unit
            else { return nil }

            let value = package.packageQuantity.value * Double(package.packageCount) + (previous?.value ?? 0)
            guard value.isFinite, value > 0, value <= 1_000_000 else { return nil }
            quantities[package.ingredientID] = PantryQuantity(value: value, unit: unit)
        }

        guard quantities.count <= 100 else { return nil }
        let items = quantities.sorted(by: { $0.key < $1.key }).map {
            ShoppingPurchasedBatch.Item(ingredientID: $0.key, quantity: $0.value)
        }
        // When items came from different snapshots, the oldest precondition forces reconciliation.
        return Transfer(rowIDs: Set(marked.map(\.id)), batch: .init(items: items), revision: oldest.revision)
    }

    private func retryDeadline(_ error: Error) -> ContinuousClock.Instant? {
        guard let value = (error as? APIClientError)?.metadata?.retryAfter,
            let seconds = Int(value), seconds > 0
        else { return nil }
        return ContinuousClock.now.advanced(by: .seconds(seconds))
    }

    private func isUnitConflict(_ error: Error) -> Bool {
        guard case .server(let payload, _) = error as? APIClientError else { return false }
        return payload.code == "unit_conflict"
    }
}

extension ShoppingPackage {
    var quantityLabel: String {
        let unit =
            switch packageQuantity.unit {
            case .grams: "г"
            case .milliliters: "мл"
            case .pieces: "шт."
            }
        let size = packageQuantity.value.formatted(.number.locale(Locale(identifier: "ru_RU")))
        return "\(packageCount) × \(size) \(unit)"
    }
}
