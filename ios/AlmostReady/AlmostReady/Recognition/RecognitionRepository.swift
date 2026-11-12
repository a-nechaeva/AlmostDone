import Foundation

nonisolated enum RecognitionKind: String, CaseIterable, Codable, Sendable {
    case receipt
    case products
}

nonisolated struct Recognition: Decodable, Sendable {
    nonisolated enum Status: String, Decodable, Sendable {
        case queued, processing, succeeded, failed
    }

    let id: String
    let kind: RecognitionKind
    let status: Status
    let pollAfterSeconds: Int
    let items: [RecognitionLine]
    let failure: Failure?

    nonisolated struct Failure: Decodable, Sendable {
        let error: APIErrorPayload
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, status, items, failure
        case pollAfterSeconds = "poll_after_seconds"
    }
}

nonisolated struct RecognitionLine: Decodable, Sendable {
    nonisolated enum Status: String, Decodable, Sendable {
        case matched, ambiguous, unmatched
    }

    nonisolated struct Candidate: Decodable, Sendable {
        let ingredientID: String
        let name: String
        let confidence: Double

        private enum CodingKeys: String, CodingKey {
            case ingredientID = "ingredient_id"
            case name, confidence
        }
    }

    let id: String
    let rawName: String
    let status: Status
    let candidates: [Candidate]
    let suggestedQuantity: PantryQuantity?

    private enum CodingKeys: String, CodingKey {
        case id = "line_id"
        case rawName = "raw_name"
        case status, candidates
        case suggestedQuantity = "suggested_quantity"
    }
}

nonisolated struct RecognitionImport: Encodable, Sendable {
    nonisolated struct Item: Encodable, Sendable {
        let lineID: String
        let ingredientID: String
        let quantity: PantryQuantity?

        private enum CodingKeys: String, CodingKey {
            case lineID = "line_id"
            case ingredientID = "ingredient_id"
            case quantity
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(lineID, forKey: .lineID)
            try container.encode(ingredientID, forKey: .ingredientID)
            try container.encode(quantity, forKey: .quantity)
        }
    }

    let recognitionID: String
    let kind: RecognitionKind
    let items: [Item]

    private enum CodingKeys: String, CodingKey {
        case recognitionID = "recognition_id"
        case kind, items
    }
}

private nonisolated struct RecognitionImportResult: Decodable, Sendable {
    let operationID: String
    let recognitionID: String
    let stateVersion: Int
    let pantry: [PantryItem]

    private enum CodingKeys: String, CodingKey {
        case operationID = "operation_id"
        case recognitionID = "recognition_id"
        case stateVersion = "state_version"
        case pantry
    }
}

@MainActor
final class RecognitionRepository {
    let session: SessionStore
    let account: AccountSession
    private let sleep: @Sendable (Duration) async throws -> Void
    private var retryDeadline: ContinuousClock.Instant?

    init(
        session: SessionStore, account: AccountSession,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.session = session
        self.account = account
        self.sleep = sleep
    }

    nonisolated deinit {}

    var isCurrent: Bool { session.isCurrent(account) }

    func upload(
        _ photo: RecognitionPhoto, kind: RecognitionKind, key: UUID
    ) async throws -> APIResponse<Recognition> {
        try await json(
            Recognition.self,
            for: APIRequest(
                path: ["recognitions"], method: .post, headers: .init(idempotencyKey: key.uuidString),
                multipartBody: .init(
                    fields: ["kind": kind.rawValue],
                    file: .init(field: "file", name: photo.fileName, contentType: photo.contentType, data: photo.data)
                )
            )
        )
    }

    func status(id: String) async throws -> APIResponse<Recognition> {
        try await json(Recognition.self, for: APIRequest(path: ["recognitions", id]))
    }

    func waitToPoll(after response: APIResponse<Recognition>) async throws {
        let seconds = max(response.value.pollAfterSeconds, Self.retrySeconds(response.metadata) ?? 0, 1)
        try await sleep(.seconds(seconds))
        try Task.checkCancellation()
    }

    func confirm(
        _ body: RecognitionImport, revision: AccountRevision, key: UUID
    ) async throws -> PantrySnapshot {
        let response = try await json(
            RecognitionImportResult.self,
            for: APIRequest(
                path: ["recognition-imports"], method: .post,
                headers: .init(ifMatch: revision.etag, idempotencyKey: key.uuidString), jsonBody: body
            )
        )
        guard response.metadata.statusCode == 200, !response.value.operationID.isEmpty,
            response.value.recognitionID == body.recognitionID
        else {
            throw APIClientError.invalidResponse(response.metadata)
        }
        let updated = try AccountRevision(etag: response.metadata.etag, stateVersion: response.value.stateVersion)
        try session.confirmMutation(response.metadata, stateVersion: updated.stateVersion, account: account)
        return PantrySnapshot(revision: updated, items: response.value.pantry)
    }

    private func json<Value: Decodable & Sendable>(
        _ type: Value.Type, for request: APIRequest
    ) async throws -> APIResponse<Value> {
        if let retryDeadline, retryDeadline > .now {
            try await sleep(ContinuousClock.now.duration(to: retryDeadline))
        }
        try Task.checkCancellation()
        do {
            return try await session.json(type, for: request, account: account)
        } catch {
            if let metadata = (error as? APIClientError)?.metadata, let seconds = Self.retrySeconds(metadata) {
                retryDeadline = .now.advanced(by: .seconds(seconds))
            }
            throw error
        }
    }

    private static func retrySeconds(_ metadata: HTTPResponseMetadata) -> Int? {
        guard let value = metadata.retryAfter, let seconds = Int(value), seconds > 0 else { return nil }
        return seconds
    }
}
