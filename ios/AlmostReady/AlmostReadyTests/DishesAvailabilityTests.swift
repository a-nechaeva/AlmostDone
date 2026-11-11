import XCTest

@testable import AlmostReady

final class DishesAvailabilityTests: XCTestCase {
    @MainActor
    func testGroupsIncludeZeroAndOneThroughThreeMissingIngredients() async {
        let ingredients = (1...4).map { Ingredient(id: "ingredient-\($0)", name: "Ингредиент \($0)") }
        let recipes = [0, 1, 3, 4].map { count in
            Recipe(
                id: "recipe-\(count)", title: "Блюдо \(count)", ingredients: Array(ingredients.prefix(count)), steps: []
            )
        }

        let availability = DishesAvailability(recipes: recipes, missingIngredients: \.ingredients)

        XCTAssertEqual(availability.ready.map(\.id), ["recipe-0"])
        XCTAssertEqual(availability.needsShopping.map(\.id), ["recipe-1", "recipe-3"])
        XCTAssertEqual(
            availability.needsShopping.map { $0.missingIngredients.map(\.id) },
            [["ingredient-1"], ["ingredient-1", "ingredient-2", "ingredient-3"]]
        )
    }

    @MainActor
    func testAvailabilityIsEmptyWhenEveryRecipeRequiresFourIngredients() async {
        let ingredients = (1...4).map { Ingredient(id: "ingredient-\($0)", name: "Ингредиент \($0)") }
        let recipe = Recipe(id: "recipe", title: "Блюдо", ingredients: ingredients, steps: [])

        let availability = DishesAvailability(recipes: [recipe], missingIngredients: \.ingredients)

        XCTAssertTrue(availability.isEmpty)
    }

    @MainActor
    func testPastaMovesBetweenGroupsWhenCheeseIsAddedAndRemoved() async {
        let store = DemoStore()
        let pastaID = "tomato-cheese-pasta"
        var availability: DishesAvailability {
            DishesAvailability(recipes: store.recipes, missingIngredients: store.missingIngredients(for:))
        }

        XCTAssertFalse(availability.ready.contains { $0.id == pastaID })
        XCTAssertEqual(availability.needsShopping.first { $0.id == pastaID }?.missingIngredients.map(\.id), ["cheese"])

        store.productIDs.insert("cheese")

        XCTAssertTrue(availability.ready.contains { $0.id == pastaID })
        XCTAssertFalse(availability.needsShopping.contains { $0.id == pastaID })

        store.productIDs.remove("cheese")

        XCTAssertFalse(availability.ready.contains { $0.id == pastaID })
        XCTAssertEqual(availability.needsShopping.first { $0.id == pastaID }?.missingIngredients.map(\.id), ["cheese"])
    }
}
