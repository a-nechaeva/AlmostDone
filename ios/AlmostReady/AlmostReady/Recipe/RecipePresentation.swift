import Foundation

struct RecipePresentation {
    struct Nutrition {
        let kilocalories: Int?
        let protein: Int?
        let fat: Int?
        let carbohydrates: Int?

        var macros: String? {
            let values = [
                protein.map { "Б \($0) г" },
                fat.map { "Ж \($0) г" },
                carbohydrates.map { "У \($0) г" }
            ].compactMap { $0 }
            return values.isEmpty ? nil : values.joined(separator: " · ")
        }
    }

    struct Servings {
        let count: Int

        var unit: String {
            RecipePresentation.countedUnit(count, one: "порция", few: "порции", many: "порций")
        }

        var description: String { "\(count) \(unit)" }

        var ingredientCaption: String {
            let unit = RecipePresentation.countedUnit(count, one: "порцию", few: "порции", many: "порций")
            return "На \(count) \(unit)"
        }
    }

    let photoName: String
    let minutes: Int?
    let servings: Servings?
    let nutrition: Nutrition?
    let allergens: [String]
    let ingredientAmounts: [Ingredient.ID: String]

    // The iOS demo recipes do not specify servings, nutrition, or recipe quantities.
    static let demo: [Recipe.ID: Self] = [
        "tomato-omelet": Self(
            photoName: "RecipeTomatoOmelet",
            minutes: 15,
            servings: nil,
            nutrition: nil,
            allergens: ["Яйца"],
            ingredientAmounts: [:]
        ),
        "tomato-cheese-pasta": Self(
            photoName: "RecipeTomatoCheesePasta",
            minutes: 20,
            servings: nil,
            nutrition: nil,
            allergens: ["Глютен", "Молоко"],
            ingredientAmounts: [:]
        )
    ]

    static func shoppingBadge(missingCount: Int) -> String {
        let unit = countedUnit(missingCount, one: "продукт", few: "продукта", many: "продуктов")
        return "Нужно докупить \(missingCount) \(unit)"
    }

    private static func countedUnit(_ count: Int, one: String, few: String, many: String) -> String {
        if (11...14).contains(count % 100) {
            return many
        }
        switch count % 10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }

    static func packagePrice(for missingIDs: Set<Ingredient.ID>) -> String? {
        guard missingIDs == [DemoData.cheese.id], let price = ShoppingDemoPlan.cheese.estimatedPrice else { return nil }
        return "≈\(shoppingRubles(price))"
    }
}
