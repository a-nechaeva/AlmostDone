import Foundation

nonisolated enum ShoppingRecommendationKind: String, Sendable {
    case singlePurchase = "single-purchase"
    case budget
}

nonisolated struct ShoppingFilters: Encodable, Equatable, Sendable {
    var query = ""
    var mode = "all"
    var maxMinutes: Int?
    var maxKcalPerServing: Double?
    var equipment = ["stove", "oven", "microwave", "no_cook"]
    var excludeAllergens: [String] = []

    private enum CodingKeys: String, CodingKey {
        case query = "q"
        case mode, equipment
        case maxMinutes = "max_minutes"
        case maxKcalPerServing = "max_kcal_per_serving"
        case excludeAllergens = "exclude_allergens"
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(query, forKey: .query)
        try values.encode(mode, forKey: .mode)
        try values.encode(maxMinutes, forKey: .maxMinutes)
        try values.encode(maxKcalPerServing, forKey: .maxKcalPerServing)
        try values.encode(equipment, forKey: .equipment)
        try values.encode(excludeAllergens, forKey: .excludeAllergens)
    }
}

nonisolated struct ShoppingMoney: Codable, Sendable {
    let minorUnits: Int
    var currency = "RUB"

    var rubles: Decimal { Decimal(minorUnits) / 100 }

    private enum CodingKeys: String, CodingKey {
        case minorUnits = "minor_units"
        case currency
    }
}

nonisolated struct ShoppingPurchaseRequest: Encodable, Sendable {
    let requestID: UUID
    let servings: Int
    let filters: ShoppingFilters
    let budget: ShoppingMoney

    private enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case servings, filters, budget
    }
}

nonisolated struct ShoppingPackage: Codable, Identifiable, Sendable {
    let key: String
    let ingredientID: String
    let packageID: String
    let name: String
    let packageQuantity: PantryQuantity
    let packageCount: Int
    let totalPrice: ShoppingMoney?

    var id: String { key }

    private enum CodingKeys: String, CodingKey {
        case key, name
        case ingredientID = "ingredient_id"
        case packageID = "package_id"
        case packageQuantity = "package_quantity"
        case packageCount = "package_count"
        case totalPrice = "total_price"
    }
}

nonisolated enum ShoppingRecommendationStatus: String, Decodable, Sendable {
    case found
    case noPlan = "no_plan"
    case insufficientData = "insufficient_data"
}

struct ShoppingSuggestion: Identifiable {
    let items: [ShoppingPackage]
    let unlockedRecipeCount: Int
    let totalCost: ShoppingMoney?

    var id: [String] { items.map(\.key) }
}

struct ShoppingRecommendation {
    let revision: AccountRevision
    let status: ShoppingRecommendationStatus
    let suggestions: [ShoppingSuggestion]
    let hasUnpricedRecipes: Bool
}

private nonisolated struct ShoppingRecommendationPayload: Decodable, Sendable {
    nonisolated struct Option: Decodable, Sendable {
        let item: ShoppingPackage
        let unlockedRecipeIDs: [String]

        private enum CodingKeys: String, CodingKey {
            case item = "shopping_item"
            case unlockedRecipeIDs = "unlocked_recipe_ids"
        }
    }

    let requestID: UUID
    let stateVersion: Int
    let servings: Int
    let status: ShoppingRecommendationStatus
    let unpricedRecipeIDs: [String]
    let options: [Option]?
    let shoppingItems: [ShoppingPackage]?
    let unlockedRecipeIDs: [String]?
    let totalCost: ShoppingMoney?

    private enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case stateVersion = "state_version"
        case servings, status, options
        case unpricedRecipeIDs = "unpriced_recipe_ids"
        case shoppingItems = "shopping_items"
        case unlockedRecipeIDs = "unlocked_recipe_ids"
        case totalCost = "total_cost"
    }
}

nonisolated struct ShoppingPurchasedBatch: Codable, Sendable {
    nonisolated struct Item: Codable, Sendable {
        let ingredientID: String
        let quantity: PantryQuantity

        private enum CodingKeys: String, CodingKey {
            case ingredientID = "ingredient_id"
            case quantity
        }
    }

    let items: [Item]
}

private nonisolated struct ShoppingMutationPayload: Decodable, Sendable {
    let stateVersion: Int

    private enum CodingKeys: String, CodingKey {
        case stateVersion = "state_version"
    }
}

struct ShoppingRepository {
    let session: SessionStore
    let account: AccountSession

    var isCurrent: Bool { session.isCurrent(account) }
    var revision: AccountRevision? { session.revision }

    func recommendations(
        _ kind: ShoppingRecommendationKind, request: ShoppingPurchaseRequest
    ) async throws -> ShoppingRecommendation {
        let response = try await session.json(
            ShoppingRecommendationPayload.self,
            for: APIRequest(path: ["recommendations", kind.rawValue], method: .post, jsonBody: request),
            account: account
        )
        let value = response.value
        guard value.requestID == request.requestID, value.servings == request.servings else {
            throw APIClientError.invalidResponse(response.metadata)
        }
        let revision = try AccountRevision(etag: response.metadata.etag, stateVersion: value.stateVersion)
        let suggestions: [ShoppingSuggestion]
        switch kind {
        case .singlePurchase:
            guard let options = value.options else { throw APIClientError.invalidResponse(response.metadata) }
            suggestions = options.map {
                ShoppingSuggestion(
                    items: [$0.item], unlockedRecipeCount: $0.unlockedRecipeIDs.count, totalCost: $0.item.totalPrice
                )
            }
        case .budget:
            guard let items = value.shoppingItems, let recipes = value.unlockedRecipeIDs else {
                throw APIClientError.invalidResponse(response.metadata)
            }
            suggestions =
                items.isEmpty
                ? []
                : [
                    ShoppingSuggestion(items: items, unlockedRecipeCount: recipes.count, totalCost: value.totalCost)
                ]
        }
        return ShoppingRecommendation(
            revision: revision, status: value.status, suggestions: suggestions,
            hasUnpricedRecipes: !value.unpricedRecipeIDs.isEmpty
        )
    }

    func reloadRevision() async throws -> AccountRevision {
        try await session.reloadRevision(for: account)
    }

    func transfer(_ batch: ShoppingPurchasedBatch, basedOn revision: AccountRevision, key: UUID) async throws {
        let response = try await session.json(
            ShoppingMutationPayload.self,
            for: APIRequest(
                path: ["me", "pantry", "purchased"], method: .post,
                headers: .init(ifMatch: revision.etag, idempotencyKey: key.uuidString), jsonBody: batch
            ),
            account: account
        )
        try session.confirmMutation(response.metadata, stateVersion: response.value.stateVersion, account: account)
    }
}
