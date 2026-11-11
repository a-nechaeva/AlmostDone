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

    @MainActor
    func testSearchAddAndRemoveCheese() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()

        let search = app.textFields["products.search"]
        let addCheese = app.buttons["products.add.cheese"]
        let homeCheese = app.staticTexts["products.home.cheese"]
        let removeCheese = app.buttons["products.remove.cheese"]
        let cancel = app.buttons["products.search.cancel"]
        let dishes = app.descendants(matching: .any)["products.dishes"].firstMatch
        let keyboard = app.keyboards.firstMatch

        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertFalse(homeCheese.exists)
        search.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertTrue(cancel.isHittable)
        XCTAssertTrue(dishes.isHittable)
        XCTAssertLessThanOrEqual(cancel.frame.maxY, keyboard.frame.minY)
        XCTAssertLessThanOrEqual(dishes.frame.maxY, keyboard.frame.minY)

        search.typeText("том")
        XCTAssertTrue(app.staticTexts["products.search.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(addCheese.exists)
        cancel.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))

        search.tap()
        search.typeText("сыр")
        XCTAssertEqual(search.value as? String, "сыр")
        XCTAssertTrue(addCheese.waitForExistence(timeout: 5))
        addCheese.tap()
        XCTAssertTrue(homeCheese.waitForExistence(timeout: 5))
        XCTAssertEqual(removeCheese.label, "Удалить продукт «Сыр»")
        removeCheese.tap()
        XCTAssertTrue(homeCheese.waitForNonExistence(timeout: 5))

        search.tap()
        search.typeText("сыр")
        XCTAssertEqual(search.value as? String, "сыр")
        XCTAssertTrue(addCheese.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(app.staticTexts["Яйца"].waitForExistence(timeout: 5))
    }
}
