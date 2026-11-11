import XCTest

final class NavigationTests: XCTestCase {
    @MainActor
    func testProductsToRecipeAndBack() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let products = app.navigationBars["Мои продукты"]
        XCTAssertTrue(products.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tabs.products"].isSelected)

        let openDishes = app.buttons["products.dishes"]
        XCTAssertTrue(openDishes.isHittable)
        openDishes.tap()

        let dishes = app.navigationBars["Блюда"]
        let dishesTab = app.buttons["tabs.dishes"]
        XCTAssertTrue(dishes.waitForExistence(timeout: 10))
        XCTAssertTrue(dishesTab.isSelected)

        let recipeLink = app.descendants(matching: .any)["dishes.recipe.tomato-omelet"].firstMatch
        XCTAssertTrue(recipeLink.isHittable)
        recipeLink.tap()

        let recipe = app.navigationBars["Рецепт"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 10))
        XCTAssertFalse(dishesTab.exists)
        let recipeTitle = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Омлет")).firstMatch
        XCTAssertTrue(recipeTitle.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Ингредиенты"].waitForExistence(timeout: 10))

        recipe.buttons.firstMatch.tap()
        XCTAssertTrue(dishes.waitForExistence(timeout: 10))
        XCTAssertTrue(dishesTab.isSelected)
    }

    @MainActor
    func testTabsKeepPurchaseAndProfileOpensProducts() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let products = app.navigationBars["Мои продукты"]
        XCTAssertTrue(products.waitForExistence(timeout: 10))

        let productsTab = app.buttons["tabs.products"]
        let dishesTab = app.buttons["tabs.dishes"]
        let shoppingTab = app.buttons["tabs.shopping"]
        let profileTab = app.buttons["tabs.profile"]
        let tabs = [productsTab, dishesTab, shoppingTab, profileTab]
        XCTAssertTrue(tabs.allSatisfy(\.isHittable))
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        XCTAssertEqual(tabs.map(\.label), ["Продукты", "Блюда", "Покупки", "Профиль"])
        let centers = tabs.map { $0.frame.midX }
        XCTAssertEqual(centers, centers.sorted())
        XCTAssertEqual(tabs.filter(\.isSelected).map(\.identifier), ["tabs.products"])

        let lastProduct = app.buttons["products.remove.olive-oil"]
        let openDishes = app.buttons["products.dishes"]
        XCTAssertTrue(lastProduct.isHittable)
        XCTAssertTrue(openDishes.isHittable)
        XCTAssertLessThanOrEqual(lastProduct.frame.maxY, openDishes.frame.minY)
        XCTAssertLessThanOrEqual(openDishes.frame.maxY, productsTab.frame.minY)

        dishesTab.tap()
        XCTAssertTrue(app.navigationBars["Блюда"].waitForExistence(timeout: 10))
        shoppingTab.tap()
        let shopping = app.navigationBars["Покупки"]
        XCTAssertTrue(shopping.waitForExistence(timeout: 10))
        XCTAssertTrue(shoppingTab.isSelected)

        let openBudget = app.buttons["Подобрать покупки под бюджет"]
        if !openBudget.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(openBudget.isHittable)
        openBudget.tap()
        let budget = app.navigationBars["План покупок"]
        XCTAssertTrue(budget.waitForExistence(timeout: 10))
        XCTAssertFalse(shoppingTab.isHittable)
        budget.buttons.firstMatch.tap()
        XCTAssertTrue(budget.waitForNonExistence(timeout: 10))

        let cheese = app.buttons["shopping.item.hard-cheese"]
        if !cheese.isHittable {
            app.scrollViews.firstMatch.swipeDown()
        }
        XCTAssertTrue(cheese.isHittable)
        cheese.tap()
        XCTAssertTrue(app.staticTexts["Покупка отмечена"].waitForExistence(timeout: 10))
        XCTAssertTrue(shoppingTab.isSelected)
        profileTab.tap()

        let profile = app.navigationBars["Профиль"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        XCTAssertTrue(profileTab.isSelected)
        app.buttons["profile.nutrition"].tap()
        let nutrition = app.navigationBars["Питание и аллергены"]
        XCTAssertTrue(nutrition.waitForExistence(timeout: 10))
        XCTAssertFalse(profileTab.exists)
        nutrition.buttons.firstMatch.tap()
        XCTAssertTrue(profile.waitForExistence(timeout: 10))

        app.buttons["profile.products"].tap()
        XCTAssertTrue(products.waitForExistence(timeout: 10))
        XCTAssertTrue(productsTab.isSelected)

        shoppingTab.tap()
        XCTAssertTrue(shopping.waitForExistence(timeout: 10))
        XCTAssertEqual(cheese.value as? String, "Куплено")
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
        XCTAssertFalse(app.buttons["tabs.products"].isHittable)
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

        dishes.tap()
        XCTAssertTrue(app.navigationBars["Блюда"].waitForExistence(timeout: 10))
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        app.buttons["tabs.products"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "сыр")
        XCTAssertFalse(keyboard.exists)
        XCTAssertTrue(addCheese.isHittable)
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
