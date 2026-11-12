import Foundation
import Observation

@MainActor
@Observable
final class ServerProfileModel {
    enum EditorPhase: Equatable {
        case closed
        case loading
        case loadFailed
        case editing
        case saving
        case saveFailed
        case reloadingConflict
        case conflictReloadFailed
        case conflictReady
    }

    struct Draft {
        let base: ProfileSnapshot
        var preferences: ProfilePreferences
    }

    let repository: ProfileRepository
    private(set) var profile: ProfileSnapshot?
    private(set) var profileLoadFailed = false
    private(set) var editorID: UUID?
    private(set) var phase: EditorPhase = .closed
    private(set) var catalogs: ProfileCatalogs?
    private(set) var draft: Draft?
    private(set) var conflict: ProfileSnapshot?
    private(set) var retryAfter: Date?
    private var pendingSave: ProfileSaveOperation?

    init(repository: ProfileRepository) {
        self.repository = repository
    }

    // As in PantryModel, avoid the implicit MainActor deinit when SwiftUI releases state on iOS 26.2.
    nonisolated deinit {}

    private var isCurrent: Bool {
        repository.session.isCurrent(repository.account)
    }

    var canEdit: Bool {
        phase == .editing || phase == .saveFailed
    }

    var canSave: Bool {
        guard canEdit, let draft else { return false }
        return draft.preferences != draft.base.value.preferences
    }

    func loadProfile() async {
        guard isCurrent, mayRetry else { return }
        profileLoadFailed = false
        do {
            let snapshot = try await repository.profile()
            guard isCurrent, !Task.isCancelled else { return }
            remember(snapshot)
        } catch {
            guard isCurrent, !Task.isCancelled else { return }
            deferRetry(for: error)
            profileLoadFailed = profile == nil
        }
    }

    func openEditor() async {
        guard isCurrent, editorID == nil else { return }
        editorID = UUID()
        guard mayRetry else {
            phase = .loadFailed
            return
        }
        await loadEditor()
    }

    func loadEditor() async {
        guard isCurrent, let id = editorID, phase == .closed || phase == .loadFailed, mayRetry else { return }
        phase = .loading
        retryAfter = nil
        do {
            async let options = repository.catalogs()
            async let loaded = repository.profile()
            let (catalogs, snapshot) = try await (options, loaded)
            guard isCurrent, editorID == id else { return }
            try requireLatest(snapshot)
            remember(snapshot)
            self.catalogs = catalogs
            draft = Draft(base: snapshot, preferences: snapshot.value.preferences)
            phase = .editing
        } catch {
            guard isCurrent, editorID == id else { return }
            deferRetry(for: error)
            phase = .loadFailed
        }
    }

    func edit(_ update: (inout ProfilePreferences) -> Void) {
        guard canEdit, isCurrent, var draft else { return }
        update(&draft.preferences)
        self.draft = draft
    }

    func closeEditor() {
        guard phase != .saving else { return }
        resetEditor()
    }

    func save() async {
        guard isCurrent, canSave, mayRetry, let draft else { return }
        let etag = draft.base.revision.etag
        let operation: ProfileSaveOperation
        if let pendingSave, pendingSave.etag == etag, pendingSave.preferences == draft.preferences {
            operation = pendingSave
        } else {
            operation = ProfileSaveOperation(etag: etag, preferences: draft.preferences)
        }
        pendingSave = operation
        phase = .saving
        retryAfter = nil
        do {
            let response = try await repository.save(operation)
            guard isCurrent else { return }
            let snapshot = try ProfileSnapshot(response)
            try repository.session.confirmMutation(
                response.metadata, stateVersion: response.value.stateVersion, account: repository.account
            )
            remember(snapshot)
            resetEditor()
        } catch {
            guard isCurrent else { return }
            deferRetry(for: error)
            if (error as? APIClientError)?.metadata?.statusCode == 412 {
                phase = .conflictReloadFailed
                await reloadConflict()
            } else {
                phase = .saveFailed
            }
        }
    }

    func reloadConflict() async {
        guard isCurrent, let id = editorID, phase == .conflictReloadFailed, mayRetry else { return }
        phase = .reloadingConflict
        retryAfter = nil
        do {
            try await repository.session.reloadRevision(for: repository.account)
            guard isCurrent, editorID == id else { return }
            let snapshot = try await repository.profile()
            guard isCurrent, editorID == id else { return }
            try requireLatest(snapshot)
            remember(snapshot)
            conflict = snapshot
            phase = .conflictReady
        } catch {
            guard isCurrent, editorID == id else { return }
            deferRetry(for: error)
            phase = .conflictReloadFailed
        }
    }

    func reconcileConflict() {
        guard isCurrent, phase == .conflictReady, let draft, let conflict else { return }
        let merged = draft.preferences.applyingChanges(
            from: draft.base.value.preferences, to: conflict.value.preferences)
        if merged == conflict.value.preferences {
            resetEditor()
            return
        }
        self.draft = Draft(base: conflict, preferences: merged)
        self.conflict = nil
        pendingSave = nil
        phase = .editing
    }

    private func remember(_ snapshot: ProfileSnapshot) {
        if profile.map({ $0.revision.stateVersion <= snapshot.revision.stateVersion }) ?? true {
            profile = snapshot
            profileLoadFailed = false
        }
    }

    private func requireLatest(_ snapshot: ProfileSnapshot) throws {
        let known = max(repository.session.revision?.stateVersion ?? 0, profile?.revision.stateVersion ?? 0)
        guard snapshot.revision.stateVersion >= known else { throw SessionError.invalidStateRevision }
    }

    private var mayRetry: Bool {
        retryAfter.map { $0 <= .now } ?? true
    }

    private func deferRetry(for error: any Error) {
        if let date = retryDate(for: error) {
            retryAfter = max(date, retryAfter ?? date)
            if profile == nil { profileLoadFailed = true }
        }
    }

    private func retryDate(for error: any Error) -> Date? {
        if case SessionError.refreshRateLimited(let until) = error { return until }
        guard let value = (error as? APIClientError)?.metadata?.retryAfter, let seconds = Int(value), seconds > 0 else {
            return nil
        }
        return .now.addingTimeInterval(TimeInterval(seconds))
    }

    private func resetEditor() {
        editorID = nil
        draft = nil
        catalogs = nil
        conflict = nil
        pendingSave = nil
        phase = .closed
    }
}
