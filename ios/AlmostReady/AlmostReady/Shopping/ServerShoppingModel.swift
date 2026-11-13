import Foundation
import Observation

@Observable
final class ServerShoppingModel {
    enum SuggestionAddition: Equatable {
        case add
        case update
        case alreadyAdded
        case marked
        case needsFreshSnapshot
        case transferPending
    }

    enum AdditionResult: Equatable {
        case added
        case alreadyAdded
        case needsFreshSnapshot
        case marked
        case transferPending
        case storageUnavailable
    }

    enum TransferState: Equatable {
        case idle
        case transferring
        case needsConfirmation
        case revisionUnavailable
        case retry
        case invalidSelection
        case rejected
        case expired
        case completed
    }

    private struct PlanChange {
        let previous: ShoppingListSnapshot.Row?
        let appliedEditID: UUID
    }

    private let repository: ShoppingRepository
    private let storage: ShoppingStorage?
    private var snapshot = ShoppingListSnapshot()
    private var canReadStorage = true
    private var planChanges: [String: PlanChange] = [:]

    private(set) var storageUnavailable = false

    private(set) var transferState: TransferState = .idle

    init(repository: ShoppingRepository, storage: ShoppingStorage? = nil) {
        self.repository = repository
        self.storage = storage
        do {
            if let storage { snapshot = try storage.load() }
        } catch {
            canReadStorage = false
            storageUnavailable = true
        }
        restoreTransferState()
    }

    // Match the lifecycle workaround used by the other SwiftUI feature models on iOS 26.2.
    nonisolated deinit {}

    var revision: AccountRevision? { repository.revision }
    var items: [ShoppingItem] { snapshot.rows.map(\.item) }
    var markedCount: Int { snapshot.rows.filter(\.isPurchased).count }
    var isSelectionLocked: Bool { snapshot.transfer != nil }
    var canUndoPlan: Bool {
        !isSelectionLocked && snapshot.rows.contains { planChanges[$0.id]?.appliedEditID == $0.editID }
    }

    func addition(for packages: [ShoppingPackage], basedOn revision: AccountRevision) -> SuggestionAddition {
        guard repository.isCurrent, isFresh(revision) else { return .needsFreshSnapshot }

        let changes = neededPackages(from: packages)
        if changes.isEmpty { return .alreadyAdded }
        if isSelectionLocked { return .transferPending }
        let existing = snapshot.rows.filter { row in changes.contains { $0.id == row.id } }
        if existing.contains(where: \.isPurchased) { return .marked }
        return existing.isEmpty ? .add : .update
    }

    func isFresh(_ snapshot: AccountRevision) -> Bool {
        guard let revision else { return false }
        let latestShoppingVersion = repository.session.shoppingRevision?.stateVersion ?? 0
        return snapshot.stateVersion >= max(revision.stateVersion, latestShoppingVersion)
    }

    /// For the graph, pass only the selected option's packages and its confirmed snapshot revision.
    ///
    /// ```swift
    /// switch shopping.add(selectedPackages, basedOn: graphRevision) {
    /// case .added: showAdded()
    /// case .alreadyAdded: showAlreadyInShopping()
    /// case .needsFreshSnapshot: reloadGraph()
    /// case .marked, .transferPending, .storageUnavailable: showShoppingError()
    /// }
    /// ```
    @discardableResult
    func add(
        _ packages: [ShoppingPackage], basedOn revision: AccountRevision, undoable: Bool = false
    ) -> AdditionResult {
        guard repository.isCurrent, isFresh(revision) else { return .needsFreshSnapshot }
        repository.session.noteShoppingRevision(revision, for: repository.account)
        switch addition(for: packages, basedOn: revision) {
        case .alreadyAdded: return .alreadyAdded
        case .needsFreshSnapshot: return .needsFreshSnapshot
        case .marked: return .marked
        case .transferPending: return .transferPending
        case .add, .update: break
        }

        var updated = snapshot
        var applied: [String: PlanChange] = [:]
        for package in neededPackages(from: packages) {
            let row = ShoppingListSnapshot.Row(package: package, revision: revision)
            if let index = updated.rows.firstIndex(where: { $0.id == package.id }) {
                applied[row.id] = PlanChange(previous: updated.rows[index], appliedEditID: row.editID)
                updated.rows[index] = row
            } else {
                applied[row.id] = PlanChange(previous: nil, appliedEditID: row.editID)
                updated.rows.append(row)
            }
        }
        guard save(updated) else { return .storageUnavailable }
        if undoable { planChanges = applied }
        return .added
    }

    func undoPlan() {
        guard canUndoPlan else { return }
        var updated = snapshot
        updated.rows = snapshot.rows.compactMap { row in
            guard let change = planChanges[row.id], change.appliedEditID == row.editID else { return row }
            return change.previous
        }
        if save(updated) { planChanges = [:] }
    }

    func contains(_ package: ShoppingPackage) -> Bool {
        guard let existing = snapshot.rows.first(where: { $0.id == package.id })?.package else { return false }
        return !needsPackage(package, comparedTo: existing)
    }

    private func neededPackages(from packages: [ShoppingPackage]) -> [ShoppingPackage] {
        var selected: [ShoppingPackage] = []
        for package in packages {
            if let index = selected.firstIndex(where: { $0.id == package.id }) {
                if needsPackage(package, comparedTo: selected[index]) { selected[index] = package }
            } else {
                selected.append(package)
            }
        }
        return selected.filter { !contains($0) }
    }

    private func needsPackage(_ package: ShoppingPackage, comparedTo existing: ShoppingPackage) -> Bool {
        package.packageQuantity != existing.packageQuantity || package.packageCount > existing.packageCount
    }

    func setPurchased(_ isPurchased: Bool, id: String) -> ShoppingItem? {
        guard !isSelectionLocked, let index = snapshot.rows.firstIndex(where: { $0.id == id }) else { return nil }
        var updated = snapshot
        if updated.rows[index].isPurchased != isPurchased {
            updated.rows[index].isPurchased = isPurchased
            updated.rows[index].editID = UUID()
        }
        guard save(updated) else { return nil }
        transferState = .idle
        return updated.rows[index].item
    }

    func confirmTransfer() async {
        guard repository.isCurrent, transferState != .transferring else { return }
        guard var transfer = snapshot.transfer ?? makeTransfer() else {
            transferState = .invalidSelection
            return
        }
        guard !transfer.hasExpired else {
            transferState = .expired
            return
        }

        if case .awaitingConfirmation(let revision) = transfer.stage {
            transfer.stage = .submitted(revision: revision, firstAttempt: .now)
        }
        guard saveTransfer(transfer) else { return }

        transferState = .transferring
        do {
            if let deadline = transfer.retryAfter, deadline > .now {
                try await Task.sleep(for: .seconds(deadline.timeIntervalSinceNow))
            }
            guard !transfer.hasExpired else {
                transferState = .expired
                return
            }
            switch transfer.stage {
            case .submitted(let revision, _):
                try await repository.transfer(transfer.batch, basedOn: revision, key: transfer.key)
                guard repository.isCurrent else { return }
                var updated = snapshot
                updated.rows.removeAll { transfer.rowIDs.contains($0.id) }
                updated.transfer = nil
                guard save(updated) else {
                    restoreTransferState()
                    return
                }
                transferState = .completed
            case .reloadRevision:
                await refreshRevision(for: transfer)
            case .awaitingConfirmation:
                break
            }
        } catch {
            guard repository.isCurrent else { return }
            transfer.retryAfter = transferRetryDate(error)
            let status = (error as? APIClientError)?.metadata?.statusCode
            switch status {
            case 412:
                transfer.stage = .reloadRevision
                if saveTransfer(transfer) { await refreshRevision(for: transfer) }
            case 422:
                if saveTransfer(nil) { transferState = .rejected }
            case 409 where isUnitConflict(error):
                if saveTransfer(nil) { transferState = .rejected }
            default:
                // Replay the same batch and precondition when the server may already have applied it.
                _ = saveTransfer(transfer)
            }
            if transferState == .transferring { restoreTransferState() }
        }
    }

    private func refreshRevision(for transfer: ShoppingListSnapshot.Transfer) async {
        var refreshed = transfer
        do {
            let revision = try await repository.reloadRevision()
            guard repository.isCurrent else { return }
            refreshed.stage = .awaitingConfirmation(revision)
            refreshed.retryAfter = nil
        } catch {
            guard repository.isCurrent else { return }
            refreshed.retryAfter = transferRetryDate(error)
        }
        _ = saveTransfer(refreshed)
        restoreTransferState()
    }

    func cancelReconciledTransfer() {
        guard transferState == .needsConfirmation || transferState == .revisionUnavailable else { return }
        if saveTransfer(nil) { transferState = .idle }
    }

    func dismissExpiredTransfer() {
        guard transferState == .expired else { return }
        if saveTransfer(nil) { transferState = .idle }
    }

    private func makeTransfer() -> ShoppingListSnapshot.Transfer? {
        let marked = snapshot.rows.filter(\.isPurchased)
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
        return ShoppingListSnapshot.Transfer(
            rowIDs: Set(marked.map(\.id)), batch: .init(items: items),
            stage: .submitted(revision: oldest.revision, firstAttempt: .now)
        )
    }

    private func restoreTransferState() {
        guard let transfer = snapshot.transfer else {
            transferState = .idle
            return
        }
        switch transfer.stage {
        case .submitted: transferState = transfer.hasExpired ? .expired : .retry
        case .reloadRevision: transferState = .revisionUnavailable
        case .awaitingConfirmation: transferState = .needsConfirmation
        }
    }

    @discardableResult
    private func saveTransfer(_ transfer: ShoppingListSnapshot.Transfer?) -> Bool {
        var updated = snapshot
        updated.transfer = transfer
        return save(updated)
    }

    private func save(_ updated: ShoppingListSnapshot) -> Bool {
        guard repository.isCurrent, canReadStorage else { return false }
        do {
            try storage?.save(updated)
            snapshot = updated
            storageUnavailable = false
            return true
        } catch {
            storageUnavailable = true
            return false
        }
    }

    private func transferRetryDate(_ error: Error) -> Date? {
        if case SessionError.refreshRateLimited(let until) = error { return until }
        guard let value = (error as? APIClientError)?.metadata?.retryAfter,
            let seconds = Int(value), seconds > 0
        else { return nil }
        return Date.now.addingTimeInterval(TimeInterval(seconds))
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
