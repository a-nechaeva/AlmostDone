import Foundation
import Observation

@Observable
final class FavoritesStore {
    struct Change {
        let entry: FavoriteEntry
        let isFavorite: Bool
    }

    struct State {
        var snapshot: FavoritesSnapshot?
        var isLoading = false
        var isSaving = false
        var loadFailed = false
        var failedChanges: [String: Change] = [:]
        var retryAfter: Date?

        func membership(of id: String) -> Bool? {
            snapshot.map { $0.entries.contains { $0.id == id } }
        }

        func change(for entry: FavoriteEntry) -> Change? {
            if let failed = failedChanges[entry.id] { return failed }
            return membership(of: entry.id).map { Change(entry: entry, isFavorite: !$0) }
        }

        func canRequest(at date: Date = .now) -> Bool {
            retryAfter.map { $0 <= date } ?? true
        }
    }

    let repository: FavoritesRepository
    let pantry: PantryModel
    private(set) var pantryDraft: PantryDraft?
    private var categories: [FavoritesCategory: State] = [:]
    @ObservationIgnored private var loads: [FavoritesCategory: Task<Void, Never>] = [:]

    init(session: SessionStore, account: AccountSession) {
        repository = FavoritesRepository(session: session, account: account)
        pantry = PantryModel(repository: ProductsRepository(session: session, account: account))
    }

    nonisolated deinit {}

    func state(for category: FavoritesCategory) -> State {
        guard repository.isCurrent else { return State() }
        return categories[category] ?? State()
    }

    func load(_ category: FavoritesCategory, force: Bool = false) async {
        guard repository.isCurrent, !Task.isCancelled else { return }
        if let load = loads[category] {
            await load.value
            return
        }
        let state = state(for: category)
        guard !state.isSaving, state.canRequest() else { return }
        guard force || state.loadFailed || (state.snapshot?.revision.stateVersion ?? -1) < latestKnownVersion else {
            return
        }

        categories[category, default: State()].isLoading = true
        // The request belongs to the account, so another screen can join it during navigation.
        let load = Task { await read(category) }
        loads[category] = load
        await load.value
    }

    private func read(_ category: FavoritesCategory) async {
        defer {
            loads[category] = nil
            categories[category]?.isLoading = false
        }
        do {
            try install(await repository.list(category), for: category)
        } catch {
            guard repository.isCurrent, !Task.isCancelled else { return }
            categories[category]?.loadFailed = true
            rememberRetryAfter(error, for: category)
        }
    }

    func set(_ change: Change, in category: FavoritesCategory) async {
        let state = state(for: category)
        guard repository.isCurrent, !state.isLoading, !state.isSaving, state.canRequest(),
            let snapshot = state.snapshot
        else { return }

        categories[category]?.isSaving = true
        defer { categories[category]?.isSaving = false }
        do {
            do {
                try await write(change, in: category, basedOn: snapshot)
            } catch let error as APIClientError where error.metadata?.statusCode == 412 {
                let refreshed = try await repository.reconcile(category)
                try install(refreshed, for: category)
                let isFavorite = refreshed.entries.contains(where: { $0.id == change.entry.id })
                if isFavorite != change.isFavorite {
                    try await write(change, in: category, basedOn: refreshed)
                }
            }
            categories[category]?.failedChanges[change.entry.id] = nil
        } catch {
            guard repository.isCurrent else { return }
            categories[category]?.failedChanges[change.entry.id] = change
            rememberRetryAfter(error, for: category)
        }
    }

    func dismissFailedChange(for id: String, in category: FavoritesCategory) {
        let state = state(for: category)
        guard repository.isCurrent, !state.isSaving else { return }
        categories[category]?.failedChanges[id] = nil
    }

    private func write(_ change: Change, in category: FavoritesCategory, basedOn base: FavoritesSnapshot) async throws {
        let revision = try await repository.set(
            change.isFavorite, id: change.entry.id, category: category,
            revision: base.revision)
        // A newer account revision can include changes from another device. Read that list before publishing it.
        if revision.stateVersion < latestKnownVersion
            || revision.stateVersion - base.revision.stateVersion > 1
        {
            try install(await repository.list(category), for: category)
            return
        }

        var entries = base.entries
        if change.isFavorite {
            if !entries.contains(where: { $0.id == change.entry.id }) {
                entries.append(change.entry)
                entries.sort { $0.id < $1.id }
            }
        } else {
            entries.removeAll { $0.id == change.entry.id }
        }
        try install(FavoritesSnapshot(revision: revision, entries: entries), for: category)
    }

    private func install(_ snapshot: FavoritesSnapshot, for category: FavoritesCategory) throws {
        guard repository.isCurrent, !Task.isCancelled else { throw SessionError.sessionChanged }
        guard snapshot.revision.stateVersion >= latestKnownVersion else { throw SessionError.invalidStateRevision }
        categories[category, default: State()].snapshot = snapshot
        categories[category]?.loadFailed = false
    }

    private var latestKnownVersion: Int {
        let account = repository.session.revision?.stateVersion ?? 0
        let lists = categories.values.compactMap { $0.snapshot?.revision.stateVersion }.max() ?? 0
        return max(account, lists)
    }

    func preparePantryDraft(for entry: FavoriteEntry) async -> Bool {
        guard repository.isCurrent, pantryDraft?.hasPendingAdd != true else { return false }
        if pantry.loadFailed {
            await pantry.reload()
        } else {
            await pantry.reloadIfNeeded()
        }
        guard repository.isCurrent, !Task.isCancelled, let snapshot = pantry.snapshot, !pantry.loadFailed else {
            return false
        }

        let ingredient: CatalogIngredient
        if entry.allowedUnits.isEmpty {
            guard
                let resolved = try? await pantry.repository.ingredient(
                    for: PantryItem(ingredientID: entry.id, name: entry.name, quantity: nil)
                )
            else { return false }
            ingredient = resolved
        } else {
            ingredient = CatalogIngredient(
                id: entry.id, name: entry.name, allowedUnits: entry.allowedUnits, nutrition: nil
            )
        }
        guard repository.isCurrent, !Task.isCancelled, pantryDraft?.hasPendingAdd != true else { return false }
        pantryDraft = PantryDraft(kind: .add(ingredient), snapshot: snapshot)
        return true
    }

    func dismissPantryDraft() {
        // Keep the key of an unconfirmed POST when the editor or Favorites is closed.
        if pantryDraft?.hasPendingAdd != true { pantryDraft = nil }
    }

    private func rememberRetryAfter(_ error: Error, for category: FavoritesCategory) {
        if case SessionError.refreshRateLimited(let until) = error {
            categories[category]?.retryAfter = until
        } else if let header = (error as? APIClientError)?.metadata?.retryAfter,
            let seconds = Int(header), seconds > 0
        {
            categories[category]?.retryAfter = .now.addingTimeInterval(Double(seconds))
        }
    }
}
