import Foundation

nonisolated enum PantryUnit: String, Codable, Sendable {
    case grams = "g"
    case milliliters = "ml"
    case pieces = "pcs"
}

nonisolated struct PantryQuantity: Codable, Equatable, Sendable {
    let value: Double
    let unit: PantryUnit
}

nonisolated struct CatalogIngredient: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let allowedUnits: [PantryUnit]

    private enum CodingKeys: String, CodingKey {
        case id, name
        case allowedUnits = "allowed_units"
    }
}

nonisolated struct IngredientSearchPage: Decodable, Sendable {
    nonisolated struct Page: Decodable, Sendable {
        let nextCursor: String?

        private enum CodingKeys: String, CodingKey {
            case nextCursor = "next_cursor"
        }
    }

    let items: [CatalogIngredient]
    let page: Page
}

nonisolated struct PantryItem: Decodable, Identifiable, Sendable {
    let ingredientID: String
    let name: String
    let quantity: PantryQuantity?

    var id: String { ingredientID }

    private enum CodingKeys: String, CodingKey {
        case ingredientID = "ingredient_id"
        case name, quantity
    }
}

struct PantrySnapshot {
    let revision: AccountRevision
    let items: [PantryItem]
}

nonisolated enum PantryWrite {
    case add(ingredientID: String, quantity: PantryQuantity?, key: UUID)
    case set(ingredientID: String, quantity: PantryQuantity?)
    case delete(ingredientID: String)
}

private nonisolated struct PantryPayload: Decodable, Sendable {
    let stateVersion: Int
    let items: [PantryItem]

    private enum CodingKeys: String, CodingKey {
        case stateVersion = "state_version"
        case items
    }
}

private nonisolated struct PantryWritePayload: Encodable, Sendable {
    var ingredientID: String? = nil
    let quantity: PantryQuantity?

    private enum CodingKeys: String, CodingKey {
        case ingredientID = "ingredient_id"
        case quantity
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(ingredientID, forKey: .ingredientID)
        try container.encode(quantity, forKey: .quantity)
    }
}

enum ProductsRepositoryError: Error {
    case ingredientUnavailable
    case staleSnapshot
}

@MainActor
final class ProductsRepository {
    let session: SessionStore
    let account: AccountSession
    private var retryAfter: ContinuousClock.Instant?

    init(session: SessionStore, account: AccountSession) {
        self.session = session
        self.account = account
    }

    // The iOS 26.2 Swift runtime can crash when SwiftUI releases objects with an implicit MainActor deinit.
    nonisolated deinit {}

    var isCurrent: Bool { session.isCurrent(account) }

    func search(_ query: String, cursor: String? = nil) async throws -> IngredientSearchPage {
        var parameters = [URLQueryItem(name: "q", value: query)]
        if let cursor { parameters.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await json(IngredientSearchPage.self, for: APIRequest(path: ["ingredients"], query: parameters))
            .value
    }

    func ingredient(for item: PantryItem) async throws -> CatalogIngredient {
        // Pantry rows contain no unit choices. Resolve by canonical ID even if names match.
        var cursor: String?
        repeat {
            let result = try await search(String(item.name.prefix(64)), cursor: cursor)
            if let ingredient = result.items.first(where: { $0.id == item.ingredientID }) {
                return ingredient
            }
            cursor = result.page.nextCursor
        } while cursor != nil
        throw ProductsRepositoryError.ingredientUnavailable
    }

    func pantry() async throws -> PantrySnapshot {
        let response = try await json(PantryPayload.self, for: APIRequest(path: ["me", "pantry"]))
        return try snapshot(from: response)
    }

    func reconcilePantry() async throws -> PantrySnapshot {
        _ = try await respectingRetryAfter { try await session.reloadRevision(for: account) }
        return try await pantry()
    }

    func write(_ write: PantryWrite, basedOn revision: AccountRevision) async throws -> PantrySnapshot {
        let path = ["me", "pantry"]
        let headers = APIRequest.Headers(ifMatch: revision.etag)
        let request: APIRequest
        switch write {
        case .add(let ingredientID, let quantity, let key):
            guard quantity.map({ $0.value > 0 }) ?? true else { throw APIClientError.invalidRequest }
            var addHeaders = headers
            addHeaders.idempotencyKey = key.uuidString
            request = APIRequest(
                path: path + ["add"], method: .post, headers: addHeaders,
                jsonBody: PantryWritePayload(ingredientID: ingredientID, quantity: quantity)
            )
        case .set(let ingredientID, let quantity):
            request = APIRequest(
                path: path + [ingredientID], method: .put, headers: headers,
                jsonBody: PantryWritePayload(quantity: quantity)
            )
        case .delete(let ingredientID):
            request = APIRequest(path: path + [ingredientID], method: .delete, headers: headers)
        }

        let response = try await json(PantryPayload.self, for: request)
        let updated = try snapshot(from: response)
        try session.confirmMutation(response.metadata, stateVersion: updated.revision.stateVersion, account: account)
        return updated
    }

    private func json<Value: Decodable & Sendable>(
        _ type: Value.Type, for request: APIRequest
    ) async throws -> APIResponse<Value> {
        try await respectingRetryAfter { try await session.json(type, for: request, account: account) }
    }

    private func respectingRetryAfter<Value>(_ operation: () async throws -> Value) async throws -> Value {
        while let retryAfter, retryAfter > .now {
            try await Task.sleep(until: retryAfter, clock: .continuous)
        }
        do {
            return try await operation()
        } catch {
            if let value = (error as? APIClientError)?.metadata?.retryAfter, let seconds = Int(value), seconds > 0 {
                let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
                retryAfter = max(retryAfter ?? deadline, deadline)
            }
            throw error
        }
    }

    private func snapshot(from response: APIResponse<PantryPayload>) throws -> PantrySnapshot {
        let revision = try AccountRevision(etag: response.metadata.etag, stateVersion: response.value.stateVersion)
        return PantrySnapshot(revision: revision, items: response.value.items)
    }
}
