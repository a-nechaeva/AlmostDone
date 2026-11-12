import Foundation
import XCTest

@testable import AlmostReady

extension ServerDishesTests {
    func testFilterLimitsRoundTripWithLocalizedInput() throws {
        let arabic = DishesFilterNumbers(locale: Locale(identifier: "ar_SA"))
        let russian = DishesFilterNumbers(locale: Locale(identifier: "ru_RU"))
        let filters = try XCTUnwrap(arabic.applying(minutes: "٣٥", kcal: "٤٢٥٫٥", to: .init()))
        XCTAssertEqual(filters.maxMinutes, 35)
        XCTAssertEqual(filters.maxKcalPerServing, Decimal(4255) / 10)
        XCTAssertEqual(
            arabic.applying(minutes: "٣٥", kcal: arabic.kcalText(filters.maxKcalPerServing), to: .init()), filters)
        XCTAssertEqual(russian.applying(minutes: "35", kcal: "425,5", to: .init()), filters)
        XCTAssertEqual(russian.applying(minutes: "35", kcal: "425.5", to: .init()), filters)
        XCTAssertNil(russian.applying(minutes: "0", kcal: "", to: .init()))
        XCTAssertNil(russian.applying(minutes: "", kcal: "0,5abc", to: .init()))
        XCTAssertNil(russian.applying(minutes: "", kcal: "-1", to: .init()))
        let tinyLimit = try XCTUnwrap(Decimal(string: "0.0000000000000000000000000000000000000001"))
        XCTAssertEqual(
            russian.applying(minutes: "", kcal: russian.kcalText(tinyLimit), to: .init())?.maxKcalPerServing, tinyLimit
        )
    }

    @MainActor
    func testFiltersUseServerAllergenIDsAndCreateANewSnapshotInEveryMode() async throws {
        let log = DishesRequestLog()
        let session = try await RecipeFixture.session { request in
            switch request.url?.path {
            case "/api/v1/allergens":
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer old-access")
                return try SessionFixture.response(
                    request,
                    body: [
                        "catalog_version": "catalog-1",
                        "items": [["id": "opaque:milk/2", "name": "Молоко", "support": "supported"]]
                    ]
                )
            case "/api/v1/recommendations":
                await log.append(request)
                return try DishesFixture.page(request, items: [])
            default:
                XCTFail("Unexpected request: \(request.httpMethod ?? "") \(request.url?.path ?? "")")
                throw URLError(.unsupportedURL)
            }
        }
        let model = try model(session)
        let allergens = try await model.repository.allergens()
        XCTAssertEqual(allergens.map(\.name), ["Молоко"])
        model.query = "  суп  "
        await model.loadIfNeeded(for: model.context)
        let original = try snapshot(model)

        model.apply(
            .init(
                maxMinutes: 35, maxKcalPerServing: Decimal(4255) / 10,
                equipment: [.stove, .microwave], excludedAllergenIDs: Set(allergens.map(\.id))
            ))
        if case .loading = model.phase {} else { XCTFail("Applying filters must invalidate the old snapshot") }

        for mode in DishesFilter.allCases {
            model.filter = mode
            await model.loadIfNeeded(for: model.context)
            XCTAssertNotEqual(try snapshot(model).firstPage.requestID, original.firstPage.requestID)
        }
        model.apply(.init(maxKcalPerServing: 0, equipment: []))
        await model.loadIfNeeded(for: model.context)
        model.apply(.init())
        await model.loadIfNeeded(for: model.context)

        let requests = await log.requests
        let bodies = try requests.map(DishesFixture.body)
        let filters = try bodies.map { try XCTUnwrap($0["filters"] as? [String: Any]) }
        XCTAssertEqual(Set(bodies.compactMap { $0["request_id"] as? String }).count, 6)
        XCTAssertEqual(filters.map { $0["mode"] as? String }, ["all", "all", "now", "buy_1_3", "buy_1_3", "buy_1_3"])
        for filter in filters[1...3] {
            XCTAssertEqual(filter["q"] as? String, "суп")
            XCTAssertEqual(filter["max_minutes"] as? Int, 35)
            XCTAssertEqual(filter["max_kcal_per_serving"] as? Double, 425.5)
            XCTAssertEqual(filter["equipment"] as? [String], ["stove", "microwave", "no_cook"])
            XCTAssertEqual(filter["exclude_allergens"] as? [String], ["opaque:milk/2"])
        }
        XCTAssertTrue(filters[4]["max_minutes"] is NSNull)
        XCTAssertEqual(filters[4]["max_kcal_per_serving"] as? Double, 0)
        XCTAssertEqual(filters[4]["equipment"] as? [String], ["no_cook"])
        XCTAssertTrue(filters[5]["max_minutes"] is NSNull)
        XCTAssertTrue(filters[5]["max_kcal_per_serving"] is NSNull)
        XCTAssertEqual(filters[5]["exclude_allergens"] as? [String], [])
    }

    @MainActor
    func testHiddenSnapshotPaginatesIndependentlyAndPassesItsContextToRecipe() async throws {
        let visiblePosts = DishesRequestLog()
        let hiddenPosts = DishesRequestLog()
        let hiddenPages = DishesRequestLog()
        let session = try await RecipeFixture.session { request in
            switch request.url?.path {
            case "/api/v1/recommendations":
                let body = try DishesFixture.body(request)
                if body["visibility"] as? String == "hidden" {
                    let index = await hiddenPosts.append(request)
                    if index == 0 { throw URLError(.notConnectedToInternet) }
                    return try DishesFixture.page(
                        request, snapshotID: "hidden", items: [Self.hiddenCard(RecipeFixture.id)],
                        cursor: "hidden+next", visibleTotal: 2, hiddenTotal: 5
                    )
                }
                await visiblePosts.append(request)
                return try DishesFixture.page(
                    request, snapshotID: "visible", items: [DishesFixture.card("visible-1", servings: 4)],
                    cursor: "visible+next", visibleTotal: 2, hiddenTotal: 5
                )
            case "/api/v1/recommendations/visible":
                XCTAssertEqual(RecipeFixture.query(request, named: "cursor"), ["visible+next"])
                return try await DishesFixture.page(
                    request, from: visiblePosts.firstRequest(), snapshotID: "visible",
                    items: [DishesFixture.card("visible-2", servings: 4)], visibleTotal: 2, hiddenTotal: 5
                )
            case "/api/v1/recommendations/hidden":
                XCTAssertEqual(RecipeFixture.query(request, named: "cursor"), ["hidden+next"])
                let index = await hiddenPages.append(request)
                if index == 0 { throw URLError(.notConnectedToInternet) }
                let posts = await hiddenPosts.requests
                return try DishesFixture.page(
                    request, from: XCTUnwrap(posts.last), snapshotID: "hidden",
                    items: [Self.hiddenCard("hidden-2")], visibleTotal: 2, hiddenTotal: 5
                )
            case RecipeFixture.detailPath:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(RecipeFixture.query(request, named: "servings"), ["4"])
                XCTAssertEqual(RecipeFixture.query(request, named: "exclude_allergens"), ["milk", "nuts"])
                return try RecipeFixture.detail(request)
            default:
                XCTFail("Unexpected request: \(request.url?.path ?? "")")
                throw URLError(.unsupportedURL)
            }
        }
        let visible = try model(session, servings: 4)
        let maxQuery = String(repeating: "я", count: 199)
        visible.query = maxQuery + " рис"
        visible.filter = .needsShopping
        visible.apply(.init(maxMinutes: 35, equipment: [.oven], excludedAllergenIDs: ["nuts", "milk"]))
        await visible.loadIfNeeded(for: visible.context)
        let first = try snapshot(visible)
        XCTAssertEqual(first.firstPage.hiddenTotal, 5)
        XCTAssertEqual(first.context.query, maxQuery)

        let hidden = ServerDishesModel(
            repository: visible.repository, initialContext: first.context, visibility: .hidden)
        await hidden.loadIfNeeded(for: hidden.context)
        if case .failed = hidden.phase {} else { XCTFail("Expected a retry after the first hidden request fails") }
        await hidden.retry()

        let result = try snapshot(hidden)
        XCTAssertNotEqual(result.firstPage.requestID, first.firstPage.requestID)
        XCTAssertNotEqual(result.firstPage.snapshotID, first.firstPage.snapshotID)
        let card = try XCTUnwrap(result.items.first)
        XCTAssertEqual(card.suitability.status, .hidden)
        XCTAssertEqual(card.suitability.reasons.map(\.message), ["Содержит молоко"])
        XCTAssertEqual(card.suitability.reasons.flatMap(\.ingredientIDs), ["cheese"])

        await hidden.loadMore()
        XCTAssertTrue(hidden.pageLoadFailed)
        XCTAssertFalse(visible.pageLoadFailed)
        XCTAssertEqual(try snapshot(hidden).items.map(\.id), [RecipeFixture.id])
        await visible.loadMore()
        await hidden.loadMore()
        XCTAssertEqual(try snapshot(visible).items.map(\.id), ["visible-1", "visible-2"])
        XCTAssertEqual(try snapshot(hidden).items.map(\.id), [RecipeFixture.id, "hidden-2"])
        await hidden.loadIfNeeded(for: hidden.context)
        await visible.loadIfNeeded(for: visible.context)
        XCTAssertEqual(try snapshot(hidden).items.map(\.id), [RecipeFixture.id, "hidden-2"])
        XCTAssertEqual(try snapshot(visible).items.map(\.id), ["visible-1", "visible-2"])

        let visibleRequests = await visiblePosts.requests
        let hiddenRequests = await hiddenPosts.requests
        XCTAssertEqual(visibleRequests.count, 1)
        XCTAssertEqual(hiddenRequests.count, 2)
        let visibleBody = try DishesFixture.body(XCTUnwrap(visibleRequests.first))
        for request in hiddenRequests {
            let body = try DishesFixture.body(request)
            XCTAssertEqual(body["visibility"] as? String, "hidden")
            XCTAssertEqual(body["servings"] as? Int, visibleBody["servings"] as? Int)
            XCTAssertEqual(body["filters"] as? NSDictionary, visibleBody["filters"] as? NSDictionary)
        }
        XCTAssertEqual(visible.advancedFilters.excludedAllergenIDs, ["nuts", "milk"])

        visible.apply(.init(excludedAllergenIDs: ["eggs"]))
        let route = result.recipeRequest(for: card)
        let repository = RecipeRepository(session: session, account: try XCTUnwrap(session.account), request: route)
        let detail = try await repository.detail(servings: route.servings)
        XCTAssertEqual(detail.recipe.servings, 4)
    }

    @MainActor
    func testHiddenContextChangeDiscardsLatePageAndCanReturnAnEmptySnapshot() async throws {
        let started = SessionResponseGate()
        let release = SessionResponseGate()
        let posts = DishesRequestLog()
        let session = try await RecipeFixture.session { request in
            switch request.url?.path {
            case "/api/v1/me/pantry/cheese":
                XCTAssertEqual(request.httpMethod, "DELETE")
                return try SessionFixture.response(
                    request, body: ["items": [], "state_version": 8], etag: #""state-8""#
                )
            case "/api/v1/recommendations":
                let index = await posts.append(request)
                let body = try DishesFixture.body(request)
                XCTAssertEqual(body["visibility"] as? String, "hidden")
                let filters = try XCTUnwrap(body["filters"] as? [String: Any])
                XCTAssertEqual(filters["max_minutes"] as? Int, 15)
                if index == 0 {
                    return try DishesFixture.page(request, items: [Self.hiddenCard("first")], cursor: "next")
                }
                return try DishesFixture.page(request, version: 8, items: [], hiddenTotal: 0)
            default:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(RecipeFixture.query(request, named: "cursor"), ["next"])
                let first = try await posts.firstRequest()
                await started.open()
                await release.wait()
                return try DishesFixture.page(request, from: first, items: [Self.hiddenCard("stale")])
            }
        }
        let visible = try model(session, servings: 4)
        visible.apply(.init(maxMinutes: 15))
        let hidden = ServerDishesModel(
            repository: visible.repository, initialContext: visible.context, visibility: .hidden
        )
        await hidden.loadIfNeeded(for: hidden.context)
        let first = try snapshot(hidden)
        let pagination = Task { await hidden.loadMore() }
        await started.wait()

        let pantry = ProductsRepository(session: session, account: visible.repository.account)
        let revision = try XCTUnwrap(session.revision)
        _ = try await pantry.write(.delete(ingredientID: "cheese"), basedOn: revision)
        XCTAssertEqual(hidden.context.stateVersion, 8)
        if case .loading = hidden.phase {} else { XCTFail("Revision change must invalidate the hidden snapshot") }
        await hidden.loadIfNeeded(for: hidden.context)
        await release.open()
        await pagination.value

        let updated = try snapshot(hidden)
        XCTAssertNotEqual(updated.firstPage.requestID, first.firstPage.requestID)
        XCTAssertEqual(updated.firstPage.stateVersion, 8)
        XCTAssertEqual(updated.firstPage.hiddenTotal, 0)
        XCTAssertTrue(updated.items.isEmpty)
        XCTAssertFalse(hidden.isLoadingMore)
        XCTAssertFalse(hidden.pageLoadFailed)
    }

    private static func hiddenCard(_ id: String) -> [String: Any] {
        var card = DishesFixture.card(id, missing: 1, servings: 4)
        card["suitability"] =
            [
                "status": "hidden",
                "reasons": [
                    [
                        "code": "allergen", "message": "Содержит молоко",
                        "ingredient_ids": ["cheese"], "restriction_ids": ["milk"]
                    ]
                ]
            ] as [String: Any]
        return card
    }
}
