import Foundation
import Observation

nonisolated struct IngredientNutrition: Decodable, Sendable {
    let kcal: Decimal
    let protein: Decimal
    let fat: Decimal
    let carbs: Decimal

    private enum CodingKeys: String, CodingKey {
        case kcal
        case protein = "protein_g"
        case fat = "fat_g"
        case carbs = "carbs_g"
    }
}

private nonisolated struct IngredientNutritionCatalogPayload: Decodable, Sendable {
    struct Ingredient: Decodable, Sendable {
        let id: String
        let nutrition: IngredientNutrition?

        private enum CodingKeys: String, CodingKey {
            case id
            case nutrition = "nutrition_per_100g"
        }
    }

    let ingredients: [Ingredient]
}

@MainActor
@Observable
final class IngredientNutritionCatalog {
    private(set) var values: [String: IngredientNutrition] = [:]
    @ObservationIgnored private var expiresAt: ContinuousClock.Instant?
    @ObservationIgnored private var loading: Task<Void, Never>?

    nonisolated deinit {}

    @discardableResult
    func load(session: SessionStore, account: AccountSession) -> Task<Void, Never>? {
        guard session.isCurrent(account), expiresAt.map({ $0 > .now }) != true else { return nil }
        if let loading { return loading }

        let task = Task {
            defer { loading = nil }
            let response = try? await session.json(
                IngredientNutritionCatalogPayload.self, for: APIRequest(path: ["catalog"]), account: account
            )
            guard session.isCurrent(account) else { return }
            guard let response else {
                values = [:]
                return
            }

            var byID: [String: IngredientNutrition] = [:]
            for ingredient in response.value.ingredients {
                byID[ingredient.id] = ingredient.nutrition
            }
            values = byID
            expiresAt = .now.advanced(by: .seconds(300))
        }
        loading = task
        return task
    }
}
