import Foundation
import Observation

@Observable
final class PantryDraft: Identifiable {
    enum Kind {
        case add(CatalogIngredient)
        case edit(PantryItem)
    }

    enum Issue: Equatable {
        case conflict
        case refreshFailed
        case unitConflict
        case uncertainAdd
        case saveFailed
    }

    fileprivate struct PendingAdd {
        let write: PantryWrite
        let revision: AccountRevision
    }

    let kind: Kind
    var quantityText: String
    var unit: PantryUnit?
    private(set) var allowedUnits: [PantryUnit] = []
    private(set) var catalogLoadFailed = false
    private(set) var isLoadingCatalog = false
    fileprivate(set) var revision: AccountRevision
    fileprivate(set) var currentItem: PantryItem?
    fileprivate(set) var issue: Issue?
    fileprivate var pendingAdd: PendingAdd?

    init(kind: Kind, snapshot: PantrySnapshot) {
        self.kind = kind
        revision = snapshot.revision
        switch kind {
        case .add(let ingredient):
            quantityText = ""
            allowedUnits = ingredient.allowedUnits
            unit = ingredient.allowedUnits.first
            currentItem = snapshot.items.first(where: { $0.id == ingredient.id })
        case .edit(let item):
            quantityText = item.quantity.map { String($0.value) } ?? ""
            unit = item.quantity?.unit
            currentItem = item
        }
    }

    nonisolated deinit {}

    var isAdding: Bool {
        if case .add = kind { return true }
        return false
    }

    var name: String {
        switch kind {
        case .add(let ingredient): ingredient.name
        case .edit(let item): item.name
        }
    }

    var ingredientID: String {
        switch kind {
        case .add(let ingredient): ingredient.id
        case .edit(let item): item.id
        }
    }

    var hasPendingAdd: Bool { pendingAdd != nil }

    var canSave: Bool {
        pendingAdd != nil || text.isEmpty || quantity != nil
    }

    var hasInvalidAmount: Bool { !text.isEmpty && amount == nil }

    fileprivate var quantity: PantryQuantity? {
        guard let amount, let unit, allowedUnits.contains(unit) else { return nil }
        return PantryQuantity(value: amount, unit: unit)
    }

    private var amount: Double? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")),
            value >= 0, value <= 1_000_000, !isAdding || value > 0
        else { return nil }
        return value
    }

    func loadUnits(from repository: ProductsRepository) async {
        guard case .edit(let item) = kind, allowedUnits.isEmpty, !isLoadingCatalog else { return }
        isLoadingCatalog = true
        catalogLoadFailed = false
        defer { isLoadingCatalog = false }
        do {
            let ingredient = try await repository.ingredient(for: item)
            guard repository.isCurrent, !Task.isCancelled else { return }
            allowedUnits = ingredient.allowedUnits
            if let unit, !allowedUnits.contains(unit) {
                self.unit = nil
            } else if unit == nil {
                unit = allowedUnits.first
            }
        } catch {
            guard repository.isCurrent, !Task.isCancelled else { return }
            catalogLoadFailed = true
        }
    }

    private var text: String { quantityText.trimmingCharacters(in: .whitespacesAndNewlines) }
}

@Observable
final class PantryModel {
    private(set) var snapshot: PantrySnapshot?
    private var loadID: UUID?
    private(set) var loadFailed = false
    private(set) var isSaving = false

    let repository: ProductsRepository

    var isLoading: Bool { loadID != nil }

    init(repository: ProductsRepository) {
        self.repository = repository
    }

    nonisolated deinit {}

    func reloadIfNeeded() async {
        let known = repository.session.revision?.stateVersion ?? 0
        guard snapshot.map({ $0.revision.stateVersion < known }) ?? true else { return }
        await reload()
    }

    func reload() async {
        guard !isSaving, !Task.isCancelled else { return }
        let id = UUID()
        loadID = id
        defer {
            if loadID == id { loadID = nil }
        }
        await updateSnapshot(request: id)
    }

    func save(_ draft: PantryDraft, deleting: Bool = false) async -> Bool {
        guard !isLoading, !isSaving, draft.issue != .refreshFailed else { return false }
        let replayingAdd = draft.hasPendingAdd
        let write: PantryWrite
        let revision: AccountRevision
        if let pending = draft.pendingAdd {
            write = pending.write
            revision = pending.revision
        } else {
            guard deleting ? !draft.isAdding : draft.canSave else { return false }
            revision = draft.revision
            if deleting {
                write = .delete(ingredientID: draft.ingredientID)
            } else if draft.isAdding {
                write = .add(ingredientID: draft.ingredientID, quantity: draft.quantity, key: UUID())
                draft.pendingAdd = .init(write: write, revision: revision)
            } else {
                write = .set(ingredientID: draft.ingredientID, quantity: draft.quantity)
            }
        }

        isSaving = true
        draft.issue = nil
        defer { isSaving = false }
        do {
            let updated = try await repository.write(write, basedOn: revision)
            guard repository.isCurrent else { return false }
            draft.pendingAdd = nil
            let installed = (try? install(updated)) != nil
            // A replay confirms the write with its original response. Another device may have changed the pantry.
            if replayingAdd || !installed { await updateSnapshot() }
            return repository.isCurrent
        } catch {
            guard repository.isCurrent else { return false }
            let status = (error as? APIClientError)?.metadata?.statusCode
            if status == 412 {
                draft.pendingAdd = nil
                await rebase(draft)
            } else if draft.hasPendingAdd && canReplayAdd(after: error) {
                draft.issue = .uncertainAdd
            } else {
                draft.pendingAdd = nil
                if case APIClientError.server(let payload, _) = error, payload.code == "unit_conflict" {
                    draft.issue = .unitConflict
                } else {
                    draft.issue = .saveFailed
                }
            }
            return false
        }
    }

    func retryRebase(_ draft: PantryDraft) async {
        guard !isLoading, !isSaving, draft.issue == .refreshFailed else { return }
        isSaving = true
        defer { isSaving = false }
        await rebase(draft)
    }

    private func rebase(_ draft: PantryDraft) async {
        do {
            let latest = try await repository.reconcilePantry()
            guard repository.isCurrent else { return }
            try install(latest)
            draft.revision = latest.revision
            draft.currentItem = latest.items.first(where: { $0.id == draft.ingredientID })
            draft.issue = .conflict
        } catch {
            guard repository.isCurrent else { return }
            draft.issue = .refreshFailed
        }
    }

    private func updateSnapshot(request id: UUID? = nil) async {
        loadFailed = false
        do {
            let updated = try await repository.pantry()
            guard loadID == id, repository.isCurrent, !Task.isCancelled else { return }
            try install(updated)
        } catch {
            guard loadID == id, repository.isCurrent, !Task.isCancelled else { return }
            loadFailed = true
        }
    }

    func install(_ updated: PantrySnapshot) throws {
        let knownVersion = repository.session.revision?.stateVersion ?? 0
        let displayedVersion = snapshot?.revision.stateVersion ?? 0
        guard updated.revision.stateVersion >= max(knownVersion, displayedVersion) else {
            throw ProductsRepositoryError.staleSnapshot
        }
        snapshot = updated
        loadFailed = false
    }

    private func canReplayAdd(after error: Error) -> Bool {
        switch error {
        case APIClientError.network, APIClientError.cancelled, is CancellationError, SessionError.invalidStateRevision,
            SessionError.refreshRateLimited:
            return true
        case APIClientError.invalidResponse(let metadata):
            guard let status = metadata?.statusCode else { return true }
            return (200..<300).contains(status) || status == 401 || status == 409 || status == 429 || status >= 500
        case APIClientError.server(let payload, let metadata):
            return payload.code == "operation_in_progress" || metadata.statusCode == 401
                || metadata.statusCode == 429 || metadata.statusCode >= 500
        default:
            return false
        }
    }
}
