import Foundation

nonisolated struct RecommendationRequest: Encodable, Sendable {
    enum Visibility: String, Codable, Sendable {
        case visible, hidden
    }

    nonisolated struct Filters: Codable, Equatable, Sendable {
        let query: String
        let mode: DishesFilter
        let maxMinutes: Int?
        let maxKcalPerServing: Decimal?
        let equipment: [String]
        let excludedAllergenIDs: [String]

        private enum CodingKeys: String, CodingKey {
            case query = "q"
            case mode, equipment
            case maxMinutes = "max_minutes"
            case maxKcalPerServing = "max_kcal_per_serving"
            case excludedAllergenIDs = "exclude_allergens"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(query, forKey: .query)
            try container.encode(mode, forKey: .mode)
            try container.encode(maxMinutes, forKey: .maxMinutes)
            try container.encode(maxKcalPerServing, forKey: .maxKcalPerServing)
            try container.encode(equipment, forKey: .equipment)
            try container.encode(excludedAllergenIDs, forKey: .excludedAllergenIDs)
        }
    }

    let requestID: UUID
    let servings: Int
    let filters: Filters
    let visibility: Visibility
    let limit = 20

    private enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case servings, filters, visibility, limit
    }
}

nonisolated struct RecommendationPage: Decodable, Sendable {
    struct Pagination: Decodable, Sendable {
        let nextCursor: String?
        let hasMore: Bool

        private enum CodingKeys: String, CodingKey {
            case nextCursor = "next_cursor"
            case hasMore = "has_more"
        }
    }

    let requestID: UUID
    let snapshotID: String
    let stateVersion: Int
    let catalogVersion: String
    let servings: Int
    let visibility: RecommendationRequest.Visibility
    let visibleTotal: Int
    let hiddenTotal: Int
    let unknownTotal: Int
    let items: [RecommendationCard]
    let page: Pagination

    private enum CodingKeys: String, CodingKey {
        case servings, visibility, items, page
        case requestID = "request_id"
        case snapshotID = "snapshot_id"
        case stateVersion = "state_version"
        case catalogVersion = "catalog_version"
        case visibleTotal = "visible_total"
        case hiddenTotal = "hidden_total"
        case unknownTotal = "unknown_total"
    }
}

nonisolated struct RecommendationCard: Decodable, Sendable, Identifiable {
    struct Suitability: Decodable, Sendable {
        enum Status: String, Decodable, Sendable {
            case allowed, unknown, hidden
        }

        let status: Status
        let reasons: [RecipeDetailDTO.Suitability.Reason]
    }

    let id: String
    let title: String
    let servings: Int
    let photoURL: String?
    let minutes: Int?
    let nutrition: RecipeDetailDTO.Nutrition?
    let buyCost: RecipeDetailDTO.Money?
    let availability: RecipeDetailDTO.Availability
    let suitability: Suitability

    private enum CodingKeys: String, CodingKey {
        case id, title, servings, minutes, availability, suitability
        case photoURL = "photo_url"
        case nutrition = "nutrition_per_serving"
        case buyCost = "buy_cost"
    }
}

enum MissingProductsError: Error {
    case contextChanged
}

@MainActor
final class RecommendationsRepository {
    let session: SessionStore
    let account: AccountSession
    private var retryAfter: ContinuousClock.Instant?

    init(session: SessionStore, account: AccountSession) {
        self.session = session
        self.account = account
    }

    nonisolated deinit {}

    func create(_ request: RecommendationRequest) async throws -> APIResponse<RecommendationPage> {
        try await fetch(
            RecommendationPage.self, for: APIRequest(path: ["recommendations"], method: .post, jsonBody: request))
    }

    func page(snapshotID: String, cursor: String) async throws -> APIResponse<RecommendationPage> {
        try await fetch(
            RecommendationPage.self,
            for: APIRequest(
                path: ["recommendations", snapshotID], query: [URLQueryItem(name: "cursor", value: cursor)])
        )
    }

    func allergens() async throws -> [ProfileAllergenOption] {
        let response = try await fetch(
            ProfileDictionary<ProfileAllergenOption>.self, for: APIRequest(path: ["allergens"]))
        return response.value.items
    }

    func graph(snapshotID: String) async throws -> APIResponse<RecommendationGraph> {
        try await fetch(RecommendationGraph.self, for: APIRequest(path: ["recommendations", snapshotID, "graph"]))
    }

    func missingProducts(
        for route: RecipeRequest, in snapshot: RecommendationPage, count: Int
    ) async throws -> [String] {
        let response = try await fetch(MissingProductsDetail.self, for: route.detailRequest)
        let detail = response.value
        let revision = try AccountRevision(etag: response.metadata.etag, stateVersion: detail.stateVersion)

        // Recipe details are calculated on read, so names must agree with the list's frozen context.
        guard revision.stateVersion == snapshot.stateVersion, detail.catalogVersion == snapshot.catalogVersion else {
            throw MissingProductsError.contextChanged
        }
        guard detail.recipe.id == route.id, detail.recipe.servings == snapshot.servings,
            detail.recipe.availability.missingCount == count
        else { throw APIClientError.invalidResponse(response.metadata) }

        var seen = Set<String>()
        let missing = detail.ingredients.filter { $0.availability == .missing && seen.insert($0.id).inserted }
        guard missing.count == count else { throw APIClientError.invalidResponse(response.metadata) }
        return missing.map(\.name)
    }

    private func fetch<Value: Decodable & Sendable>(
        _ type: Value.Type, for request: APIRequest
    ) async throws -> APIResponse<Value> {
        while let retryAfter, retryAfter > .now {
            try await Task.sleep(until: retryAfter, clock: .continuous)
        }
        do {
            return try await session.json(type, for: request, account: account)
        } catch let error as APIClientError {
            if let seconds = error.metadata?.retryAfter.flatMap(Int.init), seconds > 0 {
                let deadline = ContinuousClock.now + .seconds(seconds)
                retryAfter = max(retryAfter ?? deadline, deadline)
            }
            throw error
        }
    }
}

nonisolated private struct MissingProductsDetail: Decodable, Sendable {
    let stateVersion: Int
    let catalogVersion: String
    let recipe: RecommendationCard
    let ingredients: [RecipeDetailDTO.Ingredient]

    private enum CodingKeys: String, CodingKey {
        case stateVersion = "state_version"
        case catalogVersion = "catalog_version"
        case recipe, ingredients
    }
}
