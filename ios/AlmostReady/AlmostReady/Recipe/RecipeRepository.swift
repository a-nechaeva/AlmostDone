import Foundation

struct RecipeRequest: Hashable {
    let id: String
    let servings: Int?
    let excludedAllergenIDs: [String]

    var detailRequest: APIRequest {
        var query = excludedAllergenIDs.map { URLQueryItem(name: "exclude_allergens", value: $0) }
        if let servings {
            query.append(URLQueryItem(name: "servings", value: String(servings)))
        }
        return APIRequest(path: path, query: query)
    }

    var photoPath: [String] { path + ["photo"] }
    private var path: [String] { ["recipes", id] }
}

@MainActor
struct RecipeRepository {
    let session: SessionStore
    let account: AccountSession
    let request: RecipeRequest

    func detail() async throws -> RecipeDetailDTO {
        let response = try await session.json(RecipeDetailDTO.self, for: request.detailRequest, account: account)
        guard response.value.recipe.id == request.id else {
            throw APIClientError.invalidResponse(response.metadata)
        }
        return response.value
    }

    func photo() async throws -> APIResponse<Data> {
        try await session.publicData(path: request.photoPath)
    }
}
