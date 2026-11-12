import XCTest

final class NavigationTests: XCTestCase {
    @MainActor
    func testProductsToRecipeAndBack() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        assertRootHeader(app, tab: "products", title: "Мои продукты")
        XCTAssertTrue(app.buttons["tabs.products"].isSelected)

        let openDishes = app.buttons["products.dishes"]
        XCTAssertTrue(openDishes.isHittable)
        openDishes.tap()

        let dishes = app.staticTexts["root.title.dishes"]
        let dishesTab = app.buttons["tabs.dishes"]
        assertRootHeader(app, tab: "dishes", title: "Что приготовим?")
        XCTAssertTrue(dishesTab.isSelected)

        let recipeLink = app.descendants(matching: .any)["dishes.recipe.tomato-omelet"].firstMatch
        XCTAssertTrue(recipeLink.isHittable)
        recipeLink.tap()

        let recipe = app.navigationBars["Рецепт"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["root.brand"].isHittable)
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

        let products = app.staticTexts["root.title.products"]
        assertRootHeader(app, tab: "products", title: "Мои продукты")

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
        assertRootHeader(app, tab: "dishes", title: "Что приготовим?")
        shoppingTab.tap()
        assertRootHeader(app, tab: "shopping", title: "Что докупить")
        XCTAssertTrue(shoppingTab.isSelected)

        let openBudget = app.buttons["Подобрать покупки под бюджет"]
        if !openBudget.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(openBudget.isHittable)
        openBudget.tap()
        let budget = app.navigationBars["План покупок"]
        XCTAssertTrue(budget.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["root.brand"].isHittable)
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
        let purchasedShoppingTab = app.buttons["purchased.tabs.shopping"]
        XCTAssertTrue(purchasedShoppingTab.isHittable)
        XCTAssertTrue(purchasedShoppingTab.isSelected)
        app.buttons["purchased.tabs.profile"].tap()

        let profile = app.staticTexts["root.title.profile"]
        assertRootHeader(app, tab: "profile", title: "Профиль")
        XCTAssertTrue(profileTab.isSelected)
        app.buttons["profile.nutrition"].tap()
        let nutrition = app.navigationBars["Питание и аллергены"]
        XCTAssertTrue(nutrition.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["root.brand"].isHittable)
        XCTAssertFalse(profileTab.exists)
        nutrition.buttons.firstMatch.tap()
        XCTAssertTrue(profile.waitForExistence(timeout: 10))

        app.buttons["profile.products"].tap()
        XCTAssertTrue(products.waitForExistence(timeout: 10))
        XCTAssertTrue(productsTab.isSelected)

        shoppingTab.tap()
        XCTAssertTrue(cheese.waitForExistence(timeout: 10))
        XCTAssertTrue(shoppingTab.isSelected)
        XCTAssertEqual(cheese.value as? String, "Куплено")
    }

    @MainActor
    func testSearchAddAndRemoveCheese() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()

        let openSearch = app.buttons["products.search.open"]
        let search = app.textFields["products.search"]
        let searchTitle = app.staticTexts["products.search.title"]
        let back = app.buttons["products.search.back"]
        let clear = app.buttons["products.search.clear"]
        let addCheese = app.buttons["products.add.cheese"]
        let homeCheese = app.staticTexts["products.home.cheese"]
        let removeCheese = app.buttons["products.remove.cheese"]
        let summary = app.staticTexts["products.summary"]
        let noMatches = app.staticTexts["products.search.empty"]
        let keyboard = app.keyboards.firstMatch

        assertRootHeader(app, tab: "products", title: "Мои продукты")
        XCTAssertTrue(app.buttons["products.dishes"].isHittable)
        XCTAssertEqual(summary.label, "4 продукта · всё под рукой")
        XCTAssertFalse(homeCheese.exists)
        XCTAssertTrue(openSearch.isHittable)
        openSearch.tap()

        XCTAssertTrue(searchTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(searchTitle.label, "Добавить продукт")
        search.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["root.title.products"].isHittable)
        XCTAssertFalse(app.staticTexts["root.brand"].isHittable)
        XCTAssertFalse(app.buttons["tabs.products"].isHittable)
        XCTAssertFalse(app.buttons["products.dishes"].isHittable)
        XCTAssertTrue(back.isHittable)
        XCTAssertLessThanOrEqual(back.frame.maxY, keyboard.frame.minY)

        search.typeText("том")
        XCTAssertTrue(noMatches.waitForExistence(timeout: 5))
        XCTAssertFalse(addCheese.exists)
        XCTAssertTrue(clear.isHittable)
        XCTAssertLessThanOrEqual(clear.frame.maxY, keyboard.frame.minY)
        clear.tap()
        XCTAssertTrue(addCheese.waitForExistence(timeout: 5))
        XCTAssertTrue(keyboard.exists)

        search.typeText("сыр")
        XCTAssertEqual(search.value as? String, "сыр")
        XCTAssertTrue(addCheese.isHittable)
        XCTAssertLessThanOrEqual(addCheese.frame.maxY, keyboard.frame.minY)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "almostready-products-search"
        attachment.lifetime = .keepAlways
        add(attachment)

        addCheese.tap()

        XCTAssertTrue(homeCheese.waitForExistence(timeout: 5))
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        assertRootHeader(app, tab: "products", title: "Мои продукты")
        XCTAssertTrue(app.buttons["products.dishes"].isHittable)
        XCTAssertEqual(summary.label, "5 продуктов · всё под рукой")

        openSearch.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        search.typeText("сыр")
        XCTAssertTrue(noMatches.waitForExistence(timeout: 5))
        XCTAssertFalse(addCheese.exists)
        back.tap()

        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(removeCheese.waitForExistence(timeout: 5))
        XCTAssertEqual(removeCheese.label, "Удалить продукт «Сыр»")
        removeCheese.tap()
        XCTAssertTrue(homeCheese.waitForNonExistence(timeout: 5))
        XCTAssertEqual(summary.label, "4 продукта · всё под рукой")

        openSearch.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        search.typeText("сыр")
        XCTAssertEqual(search.value as? String, "сыр")
        XCTAssertTrue(addCheese.waitForExistence(timeout: 5))
        back.tap()
        assertRootHeader(app, tab: "products", title: "Мои продукты")
    }

    @MainActor
    func testRemovingAllProductsShowsEmptyList() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        assertRootHeader(app, tab: "products", title: "Мои продукты")
        for id in ["eggs", "tomatoes", "pasta", "olive-oil"] {
            let remove = app.buttons["products.remove.\(id)"]
            XCTAssertTrue(remove.isHittable)
            remove.tap()
        }

        XCTAssertTrue(app.staticTexts["products.home.empty"].isHittable)
        XCTAssertEqual(app.staticTexts["products.summary"].label, "0 продуктов")
        XCTAssertTrue(app.buttons["products.search.open"].isHittable)
        XCTAssertTrue(app.buttons["products.dishes"].isHittable)
    }

    @MainActor
    private func assertRootHeader(
        _ app: XCUIApplication,
        tab: String,
        title: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let heading = app.staticTexts["root.title.\(tab)"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertTrue(heading.isHittable, file: file, line: line)
        XCTAssertEqual(heading.label, title, file: file, line: line)
        XCTAssertTrue(app.staticTexts["root.brand"].isHittable, file: file, line: line)
        XCTAssertTrue(app.staticTexts["root.demo"].isHittable, file: file, line: line)
        XCTAssertFalse(app.navigationBars.firstMatch.isHittable, file: file, line: line)
    }
}
