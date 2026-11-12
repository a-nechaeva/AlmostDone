import XCTest

extension NavigationTests {
    @MainActor
    @objc func testRecipeStepsAndBackForReadyAndShoppingRecipes() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let openDishes = app.buttons["products.dishes"]
        XCTAssertTrue(openDishes.waitForExistence(timeout: 10))
        let productNames = ["Яйца", "Томаты", "Макароны", "Сыр", "Оливковое масло"]
        let initialProducts = productNames.filter { app.staticTexts[$0].exists }
        XCTAssertTrue(initialProducts.contains("Томаты"))
        openDishes.tap()

        let omeletLink = app.descendants(matching: .any)["dishes.recipe.tomato-omelet"].firstMatch
        let pastaLink = app.descendants(matching: .any)["dishes.recipe.tomato-cheese-pasta"].firstMatch
        XCTAssertTrue(omeletLink.waitForExistence(timeout: 10))
        omeletLink.tap()
        assertRecipe(
            in: app,
            title: "Омлет с томатами",
            duration: "15 мин",
            availability: "Все продукты есть",
            ingredientID: "eggs",
            ingredientStatus: "Есть дома",
            firstStep: "Нарежьте томаты и слегка обжарьте их на оливковом масле."
        )
        XCTAssertTrue(omeletLink.waitForExistence(timeout: 10))
        XCTAssertTrue(pastaLink.isHittable)

        pastaLink.tap()
        assertRecipe(
            in: app,
            title: "Паста с томатами и сыром",
            duration: "20 мин",
            availability: "Нужно докупить 1 продукт",
            ingredientID: "cheese",
            ingredientStatus: "Нужно докупить",
            firstStep: "Сварите макароны по инструкции на упаковке."
        )
        XCTAssertTrue(pastaLink.waitForExistence(timeout: 10))
        XCTAssertTrue(omeletLink.exists)
        app.buttons["tabs.products"].tap()
        XCTAssertTrue(openDishes.waitForExistence(timeout: 10))
        XCTAssertEqual(productNames.filter { app.staticTexts[$0].exists }, initialProducts)
    }

    @MainActor
    private func assertRecipe(
        in app: XCUIApplication,
        title: String,
        duration: String,
        availability: String,
        ingredientID: String,
        ingredientStatus: String,
        firstStep: String
    ) {
        let recipeBar = app.navigationBars["Рецепт"]
        let heading = app.staticTexts["Ингредиенты"]
        let stepsHeading = app.staticTexts["Как приготовить"]
        let stepsButton = app.buttons["recipe.steps"]
        XCTAssertTrue(recipeBar.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[title].exists)
        XCTAssertTrue(app.staticTexts[duration].exists)
        XCTAssertTrue(app.staticTexts[availability].exists)
        XCTAssertTrue(heading.exists)
        XCTAssertTrue(stepsButton.isHittable)
        XCTAssertFalse(stepsHeading.exists)
        attachScreenshot(named: "\(title) — детали", in: app)

        let ingredient = app.descendants(matching: .any)["recipe.ingredient.\(ingredientID)"].firstMatch
        let scroll = app.scrollViews.firstMatch
        if !ingredient.isHittable {
            scroll.swipeUp()
        }
        XCTAssertTrue(ingredient.isHittable)
        XCTAssertTrue(ingredient.label.contains(ingredientStatus))
        let lastIngredient = app.descendants(matching: .any)["recipe.ingredient.olive-oil"].firstMatch
        if !lastIngredient.isHittable || lastIngredient.frame.maxY > stepsButton.frame.minY {
            scroll.swipeUp()
        }
        XCTAssertTrue(lastIngredient.isHittable)
        XCTAssertTrue(stepsButton.isHittable)
        XCTAssertLessThanOrEqual(lastIngredient.frame.maxY, stepsButton.frame.minY)
        stepsButton.tap()

        XCTAssertTrue(stepsHeading.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[title].exists)
        XCTAssertFalse(heading.isHittable)
        XCTAssertFalse(stepsButton.isHittable)
        let step = app.descendants(matching: .any)["recipe.step.1"].firstMatch
        XCTAssertTrue(step.isHittable)
        XCTAssertTrue(step.label.contains("1"))
        XCTAssertTrue(step.label.contains(firstStep))
        attachScreenshot(named: "\(title) — шаги", in: app)

        recipeBar.buttons.firstMatch.tap()
        XCTAssertTrue(stepsButton.waitForExistence(timeout: 10))
        XCTAssertTrue(heading.exists)
        XCTAssertFalse(stepsHeading.isHittable)

        recipeBar.buttons.firstMatch.tap()
    }

    @MainActor
    private func attachScreenshot(named name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
