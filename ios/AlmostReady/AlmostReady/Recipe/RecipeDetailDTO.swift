import Foundation

nonisolated struct RecipeDetailDTO: Decodable, Sendable {
    let recipe: Card
    let ingredients: [Ingredient]
    let steps: [Step]
    let shoppingItems: [ShoppingItem]

    private enum CodingKeys: String, CodingKey {
        case recipe, ingredients, steps
        case shoppingItems = "shopping_items"
    }

    struct Card: Decodable, Sendable {
        let id: String
        let title: String
        let photoURL: String?
        let servings: Int
        let minutes: Int?
        let nutrition: Nutrition?
        let buyCost: Money?
        let availability: Availability
        let allergens: Allergens
        let suitability: Suitability

        private enum CodingKeys: String, CodingKey {
            case id, title, servings, minutes, availability, allergens, suitability
            case photoURL = "photo_url"
            case nutrition = "nutrition_per_serving"
            case buyCost = "buy_cost"
        }
    }

    struct Nutrition: Decodable, Sendable {
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

    struct Money: Decodable, Sendable {
        let minorUnits: Int

        private enum CodingKeys: String, CodingKey {
            case minorUnits = "minor_units"
        }
    }

    struct Quantity: Decodable, Sendable {
        enum Unit: String, Decodable, Sendable {
            case g, ml, pcs
        }

        let value: Decimal
        let unit: Unit
    }

    struct Availability: Decodable, Sendable {
        enum Status: String, Decodable, Sendable {
            case ready, missing, unknown
        }

        let status: Status
        let missingCount: Int
        let unknownQuantityIDs: [String]

        private enum CodingKeys: String, CodingKey {
            case status
            case missingCount = "missing_count"
            case unknownQuantityIDs = "unknown_quantity_ids"
        }
    }

    struct Allergens: Decodable, Sendable {
        enum Completeness: String, Decodable, Sendable {
            case complete, incomplete, unknown
        }

        let contains: [String]
        let completeness: Completeness
    }

    struct Suitability: Decodable, Sendable {
        struct Reason: Decodable, Sendable {
            let code: String
            let message: String
            let ingredientIDs: [String]

            private enum CodingKeys: String, CodingKey {
                case code, message
                case ingredientIDs = "ingredient_ids"
            }
        }

        let reasons: [Reason]
    }

    struct Ingredient: Decodable, Sendable {
        enum Availability: String, Decodable, Sendable {
            case enough, missing, unknown, optional
        }

        let id: String
        let name: String
        let required: Quantity?
        let available: Quantity?
        let shortage: Quantity?
        let availability: Availability
        let optional: Bool
        let originalAmount: String?

        private enum CodingKeys: String, CodingKey {
            case id = "ingredient_id"
            case name, required, available, shortage, availability, optional
            case originalAmount = "original_amount"
        }
    }

    struct Step: Decodable, Sendable {
        let number: Int
        let text: String
        let minutes: Int?
    }

    struct ShoppingItem: Decodable, Sendable {
        let key: String
        let name: String
        let packageQuantity: Quantity
        let packageCount: Int
        let totalPrice: Money?

        private enum CodingKeys: String, CodingKey {
            case key, name
            case packageQuantity = "package_quantity"
            case packageCount = "package_count"
            case totalPrice = "total_price"
        }
    }
}
