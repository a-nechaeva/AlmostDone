import Foundation
import Observation

struct PhotoImportLine: Identifiable {
    struct Ingredient {
        let id: String
        let name: String
    }

    let id: String
    let rawName: String
    private let quantityIngredientID: String?
    var ingredient: Ingredient?
    var quantity: PantryQuantity?
    var isSelected: Bool

    init(_ line: RecognitionLine) {
        id = line.id
        rawName = line.rawName
        let bestMatch = line.candidates.max { $0.confidence < $1.confidence }
        quantityIngredientID = bestMatch?.ingredientID
        ingredient = line.status == .matched ? bestMatch.map { .init(id: $0.ingredientID, name: $0.name) } : nil
        quantity = line.suggestedQuantity.flatMap { $0.value.isFinite && $0.value > 0 ? $0 : nil }
        isSelected = ingredient != nil
    }

    mutating func select(_ product: CatalogIngredient) {
        // The server converts the suggested amount into a catalog unit using its best match.
        if let quantity,
            (quantityIngredientID != nil && quantityIngredientID != product.id)
                || !product.allowedUnits.contains(quantity.unit)
        {
            self.quantity = nil
        }
        ingredient = Ingredient(id: product.id, name: product.name)
        isSelected = true
    }

    var item: RecognitionImport.Item? {
        guard isSelected, let ingredient else { return nil }
        return .init(lineID: id, ingredientID: ingredient.id, quantity: quantity)
    }
}

@Observable
final class PhotoImportModel {
    enum Phase: Equatable {
        case source, recognizing, failed, empty, review, imported
    }

    enum ImportProblem: Equatable {
        case uncertain, conflict, refreshFailed, units, alreadyImported, failed
    }

    private struct Attempt {
        let photo: RecognitionPhoto
        let kind: RecognitionKind
        let key = UUID()
        var id: String?
    }

    private struct PendingImport {
        let body: RecognitionImport
        let revision: AccountRevision
        let key = UUID()
    }

    var kind = RecognitionKind.receipt
    private(set) var phase = Phase.source
    private(set) var lines: [PhotoImportLine] = []
    private(set) var problem: ImportProblem?
    private(set) var isSaving = false

    let pantry: PantryModel
    private let repository: RecognitionRepository
    private var attempt: Attempt?
    private var recognitionID: String?
    private var revision: AccountRevision?
    private var pendingImport: PendingImport?

    init(pantry: PantryModel, repository: RecognitionRepository? = nil) {
        self.pantry = pantry
        self.repository =
            repository ?? RecognitionRepository(session: pantry.repository.session, account: pantry.repository.account)
        revision = pantry.snapshot?.revision
    }

    nonisolated deinit {}

    var canRetryRecognition: Bool { phase == .failed && attempt != nil }
    var hasPendingImport: Bool { pendingImport != nil }
    var canEdit: Bool { !isSaving && !hasPendingImport && problem != .alreadyImported }
    var canConfirm: Bool {
        phase == .review && !isSaving && problem != .refreshFailed && problem != .alreadyImported
            && (hasPendingImport || (revision != nil && lines.contains { $0.item != nil }))
    }

    func recognize(_ photo: RecognitionPhoto) async {
        guard phase == .source, repository.isCurrent, !Task.isCancelled else { return }
        attempt = Attempt(photo: photo, kind: kind)
        await resumeRecognition()
    }

    func retryRecognition() async {
        guard canRetryRecognition else { return }
        await resumeRecognition()
    }

    func chooseAnotherPhoto() {
        guard phase != .review && phase != .imported else { return }
        attempt = nil
        phase = .source
    }

    func select(_ ingredient: CatalogIngredient, for id: String) {
        guard canEdit, let index = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[index].select(ingredient)
    }

    func setSelected(_ selected: Bool, for id: String) {
        guard canEdit, let index = lines.firstIndex(where: { $0.id == id }), lines[index].ingredient != nil else {
            return
        }
        lines[index].isSelected = selected
    }

    func clearQuantity(for id: String) {
        guard canEdit, let index = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[index].quantity = nil
    }

    func confirm() async {
        guard canConfirm, repository.isCurrent, !Task.isCancelled else { return }
        let isReplay = hasPendingImport
        let pending: PendingImport
        if let pendingImport {
            pending = pendingImport
        } else {
            guard let recognitionID, let revision else { return }
            pending = PendingImport(
                body: .init(recognitionID: recognitionID, kind: kind, items: lines.compactMap(\.item)),
                revision: revision
            )
            pendingImport = pending
        }

        isSaving = true
        problem = nil
        defer { isSaving = false }
        do {
            let updated = try await repository.confirm(pending.body, revision: pending.revision, key: pending.key)
            guard checkAccount() else { return }
            pendingImport = nil
            let installed = (try? pantry.install(updated)) != nil
            phase = .imported
            // A replay may return an older snapshot than the current server state.
            if isReplay || !installed { await pantry.reload() }
            _ = checkAccount()
        } catch {
            guard checkAccount() else { return }
            await handleImportError(error)
        }
    }

    func retryRefresh() async {
        guard problem == .refreshFailed, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        await refreshConflict()
    }

    private func resumeRecognition() async {
        guard let attempt, repository.isCurrent, !Task.isCancelled else { return }
        phase = .recognizing
        do {
            var response: APIResponse<Recognition>
            if let id = attempt.id {
                response = try await repository.status(id: id)
            } else {
                response = try await repository.upload(attempt.photo, kind: attempt.kind, key: attempt.key)
            }
            while canPublish(attempt) {
                let result = response.value
                guard !result.id.isEmpty, result.kind == attempt.kind,
                    self.attempt?.id.map({ $0 == result.id }) ?? true
                else { throw APIClientError.invalidResponse(response.metadata) }

                switch result.status {
                case .queued, .processing:
                    self.attempt?.id = result.id
                    try await repository.waitToPoll(after: response)
                    guard canPublish(attempt) else { return }
                    response = try await repository.status(id: result.id)
                case .succeeded:
                    guard Set(result.items.map(\.id)).count == result.items.count else {
                        throw APIClientError.invalidResponse(response.metadata)
                    }
                    self.attempt = nil
                    recognitionID = result.id
                    lines = result.items.map(PhotoImportLine.init)
                    phase = lines.isEmpty ? .empty : .review
                    return
                case .failed:
                    self.attempt =
                        result.failure?.error.retryable == true
                        ? Attempt(photo: attempt.photo, kind: attempt.kind) : nil
                    phase = .failed
                    return
                }
            }
        } catch {
            guard canPublish(attempt) else { return }
            switch (error as? APIClientError)?.metadata?.statusCode {
            case 404, 413, 415, 422:
                self.attempt = nil
            default:
                break
            }
            phase = .failed
        }
    }

    private func canPublish(_ attempt: Attempt) -> Bool {
        checkAccount() && self.attempt?.key == attempt.key && !Task.isCancelled
    }

    private func checkAccount() -> Bool {
        guard !repository.isCurrent else { return true }
        attempt = nil
        pendingImport = nil
        recognitionID = nil
        revision = nil
        lines = []
        problem = nil
        phase = .source
        return false
    }

    private func handleImportError(_ error: Error) async {
        let apiError = error as? APIClientError
        let status = apiError?.metadata?.statusCode
        let code: String?
        if case APIClientError.server(let payload, _) = error {
            code = payload.code
        } else {
            code = nil
        }

        switch (status, code) {
        case (412, _):
            pendingImport = nil
            await refreshConflict()
        case (409, "unit_conflict"):
            pendingImport = nil
            problem = .units
        case (409, "already_imported"):
            pendingImport = nil
            problem = .alreadyImported
            await pantry.reload()
        case (409, .some(let code)) where code != "operation_in_progress":
            pendingImport = nil
            problem = .failed
        case (400, _), (404, _), (413, _), (415, _), (422, _), (428, _):
            pendingImport = nil
            problem = .failed
        default:
            problem = .uncertain
        }
    }

    private func refreshConflict() async {
        do {
            let session = repository.session
            try await session.reloadRevision(for: repository.account)
            await pantry.reload()
            guard checkAccount() else { return }
            guard let latest = pantry.snapshot?.revision, !pantry.loadFailed,
                latest.stateVersion >= (session.revision?.stateVersion ?? 0)
            else {
                problem = .refreshFailed
                return
            }
            revision = latest
            problem = .conflict
        } catch {
            guard checkAccount() else { return }
            problem = .refreshFailed
        }
    }
}
