import Foundation
import XCTest

extension NavigationTests {
    @MainActor
    func testServerGraphUsesVisibleSnapshotAndKeepsItAfterBack() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["ALMOSTREADY_GRAPH_TEST_RESPONSES"] = try GraphNavigationFixture.responses()
        app.launch()

        let dishesTab = app.buttons["tabs.dishes"]
        XCTAssertTrue(dishesTab.waitForExistence(timeout: 15))
        dishesTab.tap()

        let listRecipe = app.buttons["dishes.recipe.ready-dish"]
        XCTAssertTrue(listRecipe.waitForExistence(timeout: 10))
        let mode = app.segmentedControls["dishes.resultsMode"]
        XCTAssertTrue(mode.buttons["Список"].isSelected)
        mode.buttons["Граф"].tap()

        let hiddenLink = app.descendants(matching: .any)["dishes.hidden"].firstMatch
        XCTAssertTrue(hiddenLink.isHittable)
        hiddenLink.tap()
        let hiddenBar = app.navigationBars["Скрытые блюда"]
        XCTAssertTrue(hiddenBar.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["dishes.hidden.recipe.hidden-dish"].waitForExistence(timeout: 10))
        XCTAssertFalse(dishesTab.exists)
        hiddenBar.buttons.firstMatch.tap()

        let graphRecipe = app.buttons["dishes.graph.recipe.rice-dish"]
        reveal(graphRecipe, in: app)
        XCTAssertTrue(mode.buttons["Граф"].isSelected)
        let graphScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        graphScreenshot.name = "almostready-dishes-graph"
        graphScreenshot.lifetime = .keepAlways
        add(graphScreenshot)
        graphRecipe.tap()

        let recipeBar = app.navigationBars["Рецепт"]
        XCTAssertTrue(recipeBar.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Рис с томатами"].waitForExistence(timeout: 10))
        XCTAssertFalse(dishesTab.exists)
        recipeBar.buttons.firstMatch.tap()

        let add = app.buttons["dishes.graph.add.rice-set"]
        reveal(add, in: app)
        XCTAssertTrue(graphRecipe.exists)
        XCTAssertTrue(dishesTab.isSelected)
        add.tap()
        XCTAssertEqual(add.label, "Уже в покупках")
        XCTAssertFalse(add.isEnabled)

        app.buttons["tabs.shopping"].tap()
        let row = app.buttons["shopping.item.rice:standard"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "shopping.item.rice:standard").count, 1)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<4 {
            if element.isHittable, element.frame.maxY <= app.buttons["tabs.dishes"].frame.minY { return }
            scroll.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(element.isHittable)
    }
}

private enum GraphNavigationFixture {
    static func responses() throws -> String {
        let ready = card(id: "ready-dish", title: "Омлет", missing: 0)
        let rice = card(id: "rice-dish", title: "Рис с томатами", missing: 1)
        let expiry = Date.now.addingTimeInterval(600).ISO8601Format(
            Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        let package: [String: Any] = [
            "key": "rice:standard", "ingredient_id": "rice", "package_id": "standard", "name": "Рис",
            "package_quantity": ["value": 500, "unit": "g"], "package_count": 2, "total_price": NSNull()
        ]
        let identity: [String: Any] = [
            "request_id": "$request_id", "snapshot_id": "visible-snapshot", "expires_at": expiry,
            "state_version": 7, "catalog_version": "catalog", "servings": 2, "visibility": "visible"
        ]
        let page = identity.merging([
            "items": [ready], "visible_total": 2, "hidden_total": 1, "unknown_total": 0,
            "page": ["next_cursor": "next-page", "has_more": true]
        ]) { _, new in new }
        let hidden = page.merging([
            "snapshot_id": "hidden-snapshot", "visibility": "hidden",
            "items": [card(id: "hidden-dish", title: "Сырники", missing: 0, hidden: true)],
            "page": ["next_cursor": NSNull(), "has_more": false]
        ]) { _, new in new }
        let graph = identity.merging([
            "filters": [
                "q": "", "mode": "all", "max_minutes": NSNull(), "max_kcal_per_serving": NSNull(),
                "equipment": ["stove", "oven", "microwave", "no_cook"], "exclude_allergens": []
            ],
            "graph": [
                "scope": "snapshot", "unrepresented_recipe_ids": [],
                "nodes": [
                    ["kind": "home", "id": "home", "label": "Дома", "level": 0],
                    [
                        "kind": "purchase", "id": "rice-set", "label": "Рис", "level": 1, "dish_count": 1,
                        "cost": NSNull(), "shopping_items": [package]
                    ],
                    [
                        "kind": "recipe", "id": "ready-node", "label": "Омлет", "level": 0,
                        "recipe_id": "ready-dish", "recipe": ready
                    ],
                    [
                        "kind": "recipe", "id": "rice-node", "label": "Рис с томатами", "level": 1,
                        "recipe_id": "rice-dish", "recipe": rice
                    ]
                ],
                "edges": [
                    [
                        "kind": "extends", "source": "home", "target": "rice-set", "add": [package],
                        "add_cost": NSNull()
                    ],
                    ["kind": "unlocks", "source": "home", "target": "ready-node"],
                    ["kind": "unlocks", "source": "rice-set", "target": "rice-node"]
                ]
            ]
        ]) { _, new in new }
        let recipe: [String: Any] = [
            "state_version": 7, "catalog_version": "catalog", "recipe": rice,
            "ingredients": [], "steps": [], "shopping_items": [package]
        ]
        let responses = [
            "GET /api/v1/me/state": try response([
                "user_id": "graph-test", "state_version": 7, "catalog_version": "catalog"
            ]),
            "GET /api/v1/me/pantry": try response(["state_version": 7, "items": []]),
            "POST /api/v1/recommendations visible": try response(page, status: 201, once: true),
            "POST /api/v1/recommendations hidden": try response(hidden, status: 201, once: true),
            "GET /api/v1/recommendations/visible-snapshot/graph": try response(graph, once: true),
            "GET /api/v1/recipes/rice-dish": try response(recipe)
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: responses), as: UTF8.self)
    }

    private static func card(id: String, title: String, missing: Int, hidden: Bool = false) -> [String: Any] {
        [
            "id": id, "title": title, "servings": 2, "photo_url": NSNull(), "minutes": 15,
            "nutrition_per_serving": NSNull(), "buy_cost": NSNull(),
            "availability": [
                "status": missing == 0 ? "ready" : "missing", "missing_count": missing, "unknown_quantity_ids": []
            ],
            "suitability": [
                "status": hidden ? "hidden" : "allowed",
                "reasons": hidden
                    ? [
                        [
                            "code": "contains_allergen", "message": "Содержит молоко",
                            "ingredient_ids": ["milk"], "restriction_ids": ["milk"]
                        ]
                    ] : []
            ],
            "allergens": ["contains": [], "completeness": "complete"]
        ]
    }

    private static func response(_ body: [String: Any], status: Int = 200, once: Bool = false) throws -> [String: Any] {
        [
            "status": status, "once": once,
            "body": String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
        ]
    }
}
