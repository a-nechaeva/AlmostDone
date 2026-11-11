import XCTest

extension NavigationTests {
    @MainActor
    @objc func testRecipeCardsOpenTheirOwnDetailsAndPreserveProductsOnBack() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let products = app.navigationBars["Мои продукты"]
        XCTAssertTrue(products.waitForExistence(timeout: 10))
        let productNames = ["Яйца", "Томаты", "Макароны", "Сыр", "Оливковое масло"]
        let initialProducts = productNames.filter { app.staticTexts[$0].exists }
        XCTAssertTrue(initialProducts.contains("Томаты"))
        app.descendants(matching: .any)["products.dishes"].firstMatch.tap()

        let dishes = app.navigationBars["Блюда"]
        let recipe = app.navigationBars["Рецепт"]
        XCTAssertTrue(dishes.waitForExistence(timeout: 10))
        let omeletLink = app.descendants(matching: .any)["dishes.recipe.tomato-omelet"].firstMatch
        let pastaLink = app.descendants(matching: .any)["dishes.recipe.tomato-cheese-pasta"].firstMatch
        XCTAssertTrue(omeletLink.isHittable)
        omeletLink.tap()
        XCTAssertTrue(recipe.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Омлет с томатами"].exists)
        XCTAssertTrue(app.staticTexts["15 мин"].exists)
        XCTAssertTrue(app.staticTexts["Все продукты есть"].exists)
        let eggs = app.descendants(matching: .any)["recipe.ingredient.eggs"].firstMatch
        XCTAssertTrue(eggs.exists)
        XCTAssertTrue(eggs.label.contains("Есть дома"))

        recipe.buttons.firstMatch.tap()
        XCTAssertTrue(dishes.waitForExistence(timeout: 10))
        XCTAssertTrue(pastaLink.isHittable)
        pastaLink.tap()
        XCTAssertTrue(recipe.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Паста с томатами и сыром"].exists)
        XCTAssertTrue(app.staticTexts["20 мин"].exists)
        let cheese = app.descendants(matching: .any)["recipe.ingredient.cheese"].firstMatch
        if !cheese.exists {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(cheese.exists)
        XCTAssertTrue(cheese.label.contains("Нужно докупить"))

        app.buttons["recipe.steps"].tap()
        XCTAssertTrue(app.staticTexts["Как приготовить"].isHittable)
        let pastaStep = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Сварите макароны по инструкции на упаковке."))
            .firstMatch
        XCTAssertTrue(pastaStep.exists)

        recipe.buttons.firstMatch.tap()
        XCTAssertTrue(dishes.waitForExistence(timeout: 10))
        XCTAssertTrue(omeletLink.exists)
        XCTAssertTrue(pastaLink.exists)
        dishes.buttons.firstMatch.tap()
        XCTAssertTrue(products.waitForExistence(timeout: 10))
        XCTAssertEqual(productNames.filter { app.staticTexts[$0].exists }, initialProducts)
    }
}
