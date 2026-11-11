import XCTest

final class NavigationTests: XCTestCase {
    @MainActor
    func testProductsToRecipeAndBack() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let products = app.navigationBars["Мои продукты"]
        XCTAssertTrue(products.waitForExistence(timeout: 10))

        let dishesLink = app.descendants(matching: .any)["products.dishes"].firstMatch
        XCTAssertTrue(dishesLink.isHittable)
        dishesLink.tap()

        let dishes = app.navigationBars["Блюда"]
        XCTAssertTrue(dishes.waitForExistence(timeout: 10))

        let recipeLink = app.descendants(matching: .any)["dishes.recipe.tomato-omelet"].firstMatch
        XCTAssertTrue(recipeLink.isHittable)
        recipeLink.tap()

        let recipe = app.navigationBars["Рецепт"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 10))
        let recipeTitle = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Омлет")).firstMatch
        XCTAssertTrue(recipeTitle.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Ингредиенты"].waitForExistence(timeout: 10))

        recipe.buttons.firstMatch.tap()
        XCTAssertTrue(dishes.waitForExistence(timeout: 10))

        dishes.buttons.firstMatch.tap()
        XCTAssertTrue(products.waitForExistence(timeout: 10))
    }
}
