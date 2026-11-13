import Foundation
import XCTest

@testable import AlmostReady

final class ServerDishesTests: XCTestCase {
    @MainActor
    func testModesSendCompleteFiltersAndKeepServerGroupsAndTotals() async throws {
        let log = DishesRequestLog()
        let session = try await RecipeFixture.session { request in
            await log.append(request)
            XCTAssertEqual(request.url?.path, "/api/v1/recommendations")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer old-access")

            let body = try DishesFixture.body(request)
            let filters = try XCTUnwrap(body["filters"] as? [String: Any])
            XCTAssertEqual(Set(body.keys), ["request_id", "filters", "visibility", "limit", "servings"])
            XCTAssertEqual(
                Set(filters.keys),
                [
                    "q", "mode", "max_minutes", "max_kcal_per_serving", "equipment", "exclude_allergens"
                ])
            XCTAssertEqual(body["limit"] as? Int, 20)
            XCTAssertEqual(body["servings"] as? Int, 2)
            XCTAssertEqual(body["visibility"] as? String, "visible")
            XCTAssertEqual(filters["q"] as? String, "рис + сыр")
            XCTAssertTrue(filters["max_minutes"] is NSNull)
            XCTAssertTrue(filters["max_kcal_per_serving"] is NSNull)
            XCTAssertEqual(filters["equipment"] as? [String], ["stove", "oven", "microwave", "no_cook"])
            XCTAssertEqual(filters["exclude_allergens"] as? [String], [])

            let ready = DishesFixture.card("ready", missing: 0, unknownQuantityIDs: ["cheese"])
            let one = DishesFixture.card("one", missing: 1)
            let three = DishesFixture.card("three", missing: 3)
            let four = DishesFixture.card("four", missing: 4)
            let unknown = DishesFixture.card(
                "unknown", missing: 2, hasMetrics: false, suitabilityUnknown: true, availabilityUnknown: true
            )
            switch filters["mode"] as? String {
            case "all":
                return try DishesFixture.page(request, items: [ready, one, three, four, unknown], unknownTotal: 1)
            case "now":
                return try DishesFixture.page(request, items: [ready])
            case "buy_1_3":
                return try DishesFixture.page(request, items: [one, three])
            default:
                throw URLError(.badURL)
            }
        }
        let model = try model(session)
        model.query = "  рис + сыр\n"
        await model.loadIfNeeded(for: model.context)
        let all = try snapshot(model)
        XCTAssertEqual(all.groups.keys.sorted(), [.ready, .missing(1), .missing(3), .missing(4), .unknown])
        XCTAssertEqual(all.groups[.ready]?.first?.availability.unknownQuantityIDs, ["cheese"])
        let unknown = try XCTUnwrap(all.groups[.unknown]?.first)
        XCTAssertNil(unknown.minutes)
        XCTAssertNil(unknown.nutrition)
        XCTAssertNil(unknown.buyCost)
        XCTAssertEqual(unknown.suitability.status, .unknown)
        XCTAssertEqual(unknown.availability.missingCount, 2)
        XCTAssertEqual(all.firstPage.visibleTotal, 5)
        XCTAssertEqual(all.firstPage.hiddenTotal, 2)
        XCTAssertEqual(all.firstPage.unknownTotal, 1)

        model.filter = .ready
        await model.loadIfNeeded(for: model.context)
        XCTAssertEqual(try snapshot(model).items.map(\.id), ["ready"])
        model.filter = .needsShopping
        await model.loadIfNeeded(for: model.context)
        let buy = try snapshot(model)
        XCTAssertEqual(buy.items.map(\.id), ["one", "three"])

        // Returning from the recipe uses the same context and snapshot.
        await model.loadIfNeeded(for: model.context)
        XCTAssertEqual(try snapshot(model).firstPage.snapshotID, buy.firstPage.snapshotID)
        XCTAssertEqual(model.filter, .needsShopping)
        XCTAssertEqual(model.query, "  рис + сыр\n")
        let requests = await log.requests
        XCTAssertEqual(requests.count, 3)
        let ids = try requests.map { try XCTUnwrap(DishesFixture.body($0)["request_id"] as? String) }
        XCTAssertTrue(ids.allSatisfy { UUID(uuidString: $0) != nil })
        XCTAssertEqual(Set(ids).count, 3)
    }

    @MainActor
    func testPageFailuresKeepCardsAndRetryTheSameCursor() async throws {
        let log = DishesRequestLog()
        let session = try await RecipeFixture.session { request in
            let index = await log.append(request)
            if index == 0 {
                return try DishesFixture.page(
                    request, snapshotID: "opaque/id", items: [DishesFixture.card("first")],
                    cursor: "next+/=", visibleTotal: 2
                )
            }

            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://example.test/api/v1/recommendations/opaque%2Fid?cursor=next%2B%2F%3D"
            )
            XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer old-access")
            let first = try await log.firstRequest()
            let items = [DishesFixture.card("next", missing: 3)]
            switch index {
            case 1:
                throw URLError(.notConnectedToInternet)
            case 2:
                return try DishesFixture.page(
                    request, from: first, requestID: UUID().uuidString, snapshotID: "opaque/id", items: items
                )
            case 3:
                return try DishesFixture.page(request, from: first, snapshotID: "other", items: items)
            case 4:
                return try DishesFixture.page(request, from: first, snapshotID: "opaque/id", version: 8, items: items)
            case 5:
                return try DishesFixture.page(
                    request, from: first, snapshotID: "opaque/id", catalogVersion: "other-catalog", items: items
                )
            default:
                return try DishesFixture.page(
                    request, from: first, snapshotID: "opaque/id", items: items, visibleTotal: 2)
            }
        }
        let model = try model(session)
        await model.loadIfNeeded(for: model.context)

        for _ in 0..<5 {
            await model.loadMore()
            let previous = try snapshot(model)
            XCTAssertEqual(previous.items.map(\.id), ["first"])
            XCTAssertEqual(previous.firstPage.visibleTotal, 2)
            XCTAssertEqual(previous.nextCursor, "next+/=")
            XCTAssertTrue(model.pageLoadFailed)
            XCTAssertFalse(model.isLoadingMore)
        }

        await model.loadMore()
        let loaded = try snapshot(model)
        XCTAssertEqual(loaded.items.map(\.id), ["first", "next"])
        XCTAssertNil(loaded.nextCursor)
        XCTAssertFalse(model.pageLoadFailed)
        XCTAssertFalse(model.isLoadingMore)
    }

    @MainActor
    func testExpiredOrChangedSnapshotRestartsFromFirstPage() async throws {
        for code in ["snapshot_expired", "context_changed"] {
            let log = DishesRequestLog()
            let version = code == "context_changed" ? 8 : 7
            let session = try await RecipeFixture.session { request in
                switch await log.append(request) {
                case 0:
                    return try DishesFixture.page(request, items: [DishesFixture.card("old")], cursor: "next")
                case 1:
                    XCTAssertEqual(request.httpMethod, "GET")
                    return try SessionFixture.error(request, status: 409, code: code)
                default:
                    XCTAssertEqual(request.httpMethod, "POST")
                    return try DishesFixture.page(request, version: version, items: [DishesFixture.card("new")])
                }
            }
            let model = try model(session)
            model.query = "яблоко"
            model.filter = .ready
            await model.loadIfNeeded(for: model.context)
            let previous = try snapshot(model)
            await model.loadMore()
            let current = try snapshot(model)

            XCTAssertNotEqual(current.firstPage.requestID, previous.firstPage.requestID)
            XCTAssertNotEqual(current.firstPage.snapshotID, previous.firstPage.snapshotID)
            XCTAssertEqual(current.firstPage.stateVersion, version)
            XCTAssertEqual(current.items.map(\.id), ["new"])
            XCTAssertNil(current.nextCursor)
            XCTAssertFalse(model.pageLoadFailed)
            XCTAssertFalse(model.isLoadingMore)
            let requests = await log.requests
            XCTAssertEqual(requests.map(\.httpMethod), ["POST", "GET", "POST"])
            let restarted = try XCTUnwrap(requests.last)
            let filters = try XCTUnwrap(DishesFixture.body(restarted)["filters"] as? [String: Any])
            XCTAssertEqual(filters["q"] as? String, "яблоко")
            XCTAssertEqual(filters["mode"] as? String, "now")
        }
    }

    @MainActor
    func testReappearingDuringConflictRecoveryDoesNotCreateAnotherSnapshot() async throws {
        let recoveryStarted = SessionResponseGate()
        let releaseRecovery = SessionResponseGate()
        let log = DishesRequestLog()
        let session = try await RecipeFixture.session { request in
            switch await log.append(request) {
            case 0:
                return try DishesFixture.page(request, items: [DishesFixture.card("old")], cursor: "next")
            case 1:
                return try SessionFixture.error(request, status: 409, code: "snapshot_expired")
            case 2:
                await recoveryStarted.open()
                await releaseRecovery.wait()
                return try DishesFixture.page(request, items: [DishesFixture.card("recovered")])
            default:
                XCTFail("Reappearing reused the context and should not create another snapshot")
                throw URLError(.unsupportedURL)
            }
        }
        let model = try model(session)
        await model.loadIfNeeded(for: model.context)
        let pagination = Task { await model.loadMore() }
        await recoveryStarted.wait()

        await model.loadIfNeeded(for: model.context)
        await releaseRecovery.open()
        await pagination.value

        XCTAssertEqual(try snapshot(model).items.map(\.id), ["recovered"])
        let requests = await log.requests
        XCTAssertEqual(requests.map(\.httpMethod), ["POST", "GET", "POST"])
    }

    @MainActor
    func testLateSearchCannotReplaceCurrentResult() async throws {
        let firstStarted = SessionResponseGate()
        let releaseFirst = SessionResponseGate()
        let session = try await RecipeFixture.session { request in
            let filters = try XCTUnwrap(DishesFixture.body(request)["filters"] as? [String: Any])
            let query = try XCTUnwrap(filters["q"] as? String)
            if query == "первый" {
                await firstStarted.open()
                await releaseFirst.wait()
            }
            return try DishesFixture.page(request, items: [DishesFixture.card(query)])
        }
        let model = try model(session)
        model.query = "первый"
        let oldContext = model.context
        let oldLoad = Task { await model.loadIfNeeded(for: oldContext) }
        await firstStarted.wait()

        model.query = "второй"
        await model.loadIfNeeded(for: model.context)
        await releaseFirst.open()
        await oldLoad.value

        XCTAssertEqual(try snapshot(model).items.map(\.id), ["второй"])
    }

    @MainActor
    func testConfirmedPantryAndProfileRevisionsInvalidateInFlightRequests() async throws {
        let oldPageStarted = SessionResponseGate()
        let releaseOldPage = SessionResponseGate()
        let log = DishesRequestLog()
        let session = try await RecipeFixture.session { request in
            switch request.url?.path {
            case "/api/v1/me/pantry/cheese":
                XCTAssertEqual(request.httpMethod, "DELETE")
                return try SessionFixture.response(
                    request, body: ["items": [], "state_version": 8], etag: #""state-8""#
                )
            case "/api/v1/me":
                XCTAssertEqual(request.httpMethod, "PATCH")
                let body = try DishesFixture.body(request)
                let preferences = try XCTUnwrap(body["preferences"] as? [String: Any])
                XCTAssertEqual(preferences["excluded_allergens"] as? [String], ["milk"])
                return try SessionFixture.response(
                    request,
                    body: [
                        "user_id": SessionFixture.original.userID, "display_name": NSNull(),
                        "state_version": 9, "preferences": preferences, "unsupported_restrictions": []
                    ],
                    etag: #""state-9""#
                )
            default:
                let index = await log.append(request)
                switch index {
                case 0:
                    return try DishesFixture.page(request, items: [DishesFixture.card("old")], cursor: "next")
                case 1:
                    let first = try await log.firstRequest()
                    await oldPageStarted.open()
                    await releaseOldPage.wait()
                    return try DishesFixture.page(request, from: first, items: [DishesFixture.card("old-page")])
                case 2:
                    return try DishesFixture.page(request, version: 8, items: [DishesFixture.card("pantry")])
                default:
                    return try DishesFixture.page(request, version: 9, items: [DishesFixture.card("profile")])
                }
            }
        }
        let account = try XCTUnwrap(session.account)
        let model = try model(session)
        await model.loadIfNeeded(for: model.context)
        let oldPage = Task { await model.loadMore() }
        await oldPageStarted.wait()

        let pantry = ProductsRepository(session: session, account: account)
        let revision = try XCTUnwrap(session.revision)
        _ = try await pantry.write(.delete(ingredientID: "cheese"), basedOn: revision)
        XCTAssertEqual(model.context.stateVersion, 8)
        if case .loading = model.phase {} else { XCTFail("Previous cards should disappear on revision change") }
        await model.loadIfNeeded(for: model.context)
        await releaseOldPage.open()
        await oldPage.value
        XCTAssertEqual(try snapshot(model).items.map(\.id), ["pantry"])

        let profile = ProfileRepository(session: session, account: account)
        let preferences = ProfilePreferences(
            foodType: "any", excludedAllergens: ["milk"], glutenFree: false,
            lactoseFree: false, diabetes: false, dietTableID: nil
        )
        let profileRevision = try XCTUnwrap(session.revision)
        let response = try await profile.save(.init(etag: profileRevision.etag, preferences: preferences))
        try session.confirmMutation(response.metadata, stateVersion: response.value.stateVersion, account: account)
        XCTAssertEqual(model.context.stateVersion, 9)
        await model.loadIfNeeded(for: model.context)
        XCTAssertEqual(try snapshot(model).items.map(\.id), ["profile"])
    }

    @MainActor
    func testResponseFromPreviousAccountCannotPublish() async throws {
        let started = SessionResponseGate()
        let release = SessionResponseGate()
        let session = try await RecipeFixture.session { request in
            switch request.url?.path {
            case "/api/v1/auth/logout":
                return try SessionFixture.response(request, status: 204)
            case "/api/v1/auth/yandex":
                return try SessionFixture.sessionResponse(request, SessionFixture.another)
            default:
                let token = request.value(forHTTPHeaderField: "Authorization")
                if token == "Bearer old-access" {
                    await started.open()
                    await release.wait()
                    return try DishesFixture.page(request, items: [DishesFixture.card("old-account")])
                }
                XCTAssertEqual(token, "Bearer other-access")
                return try DishesFixture.page(request, items: [DishesFixture.card("new-account")])
            }
        }
        let oldAccount = try XCTUnwrap(session.account)
        let oldModel = try model(session)
        let request = Task { await oldModel.loadIfNeeded(for: oldModel.context) }
        await started.wait()

        _ = try await session.signOut()
        await session.signIn()
        await release.open()
        await request.value
        let currentAccount = try XCTUnwrap(session.account)
        XCTAssertNotEqual(currentAccount, oldAccount)
        if case .loading = oldModel.phase {} else { XCTFail("Previous account's snapshot became visible") }

        let currentModel = try model(session)
        await currentModel.loadIfNeeded(for: currentModel.context)
        XCTAssertEqual(try snapshot(currentModel).items.map(\.id), ["new-account"])
    }

    @MainActor
    func testFirstPageFailureCanRetryAndRejectsOlderVersion() async throws {
        let log = DishesRequestLog()
        let session = try await RecipeFixture.session { request in
            switch await log.append(request) {
            case 0:
                throw URLError(.notConnectedToInternet)
            case 1:
                return try DishesFixture.page(request, version: 6, items: [DishesFixture.card("stale")])
            default:
                return try DishesFixture.page(request, items: [])
            }
        }
        let model = try model(session)
        await model.loadIfNeeded(for: model.context)
        if case .failed = model.phase {} else { XCTFail("Expected retry after network error") }
        await model.retry()
        if case .failed = model.phase {} else { XCTFail("An older version must not be displayed") }
        await model.retry()
        XCTAssertTrue(try snapshot(model).items.isEmpty)
    }

    @MainActor
    func testRecipeRequestUsesCardIDAndContextFromTheSnapshot() async throws {
        let session = try await RecipeFixture.session { request in
            if request.url?.path == RecipeFixture.detailPath {
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer old-access")
                XCTAssertEqual(RecipeFixture.query(request, named: "servings"), ["4"])
                XCTAssertEqual(RecipeFixture.query(request, named: "exclude_allergens"), ["milk", "nuts"])
                return try RecipeFixture.detail(request)
            }
            let body = try DishesFixture.body(request)
            let filters = try XCTUnwrap(body["filters"] as? [String: Any])
            XCTAssertEqual(body["servings"] as? Int, 4)
            XCTAssertEqual(filters["exclude_allergens"] as? [String], ["milk", "nuts"])
            return try DishesFixture.page(
                request, items: [DishesFixture.card(RecipeFixture.id, missing: 1, servings: 4)]
            )
        }
        let model = try model(session, servings: 4, exclusions: ["milk", "nuts"])
        await model.loadIfNeeded(for: model.context)
        let loaded = try snapshot(model)
        let card = try XCTUnwrap(loaded.items.first)
        let route = loaded.recipeRequest(for: card)
        XCTAssertEqual(route.id, RecipeFixture.id)
        let repository = RecipeRepository(session: session, account: try XCTUnwrap(session.account), request: route)
        let detail = try await repository.detail(servings: route.servings)
        XCTAssertEqual(detail.recipe.servings, 4)
        XCTAssertEqual(detail.ingredients.first { $0.availability == .missing }?.name, "Рис")
    }

    @MainActor
    func testMissingProductsRequireMatchingDetailsAndCanRefreshStaleSnapshot() async throws {
        let log = DishesRequestLog()
        let creations = DishesRequestLog()
        let session = try await RecipeFixture.session { request in
            if request.httpMethod == "POST" {
                let index = await creations.append(request)
                return try DishesFixture.page(
                    request, version: index == 0 ? 7 : 8, catalogVersion: "fixture-catalog",
                    items: [DishesFixture.card(RecipeFixture.id, missing: 1, servings: 4)]
                )
            }

            XCTAssertEqual(request.url?.path, RecipeFixture.detailPath)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(RecipeFixture.query(request, named: "servings"), ["4"])
            XCTAssertEqual(RecipeFixture.query(request, named: "exclude_allergens"), ["milk"])
            let index = await log.append(request)
            let (data, response) = try RecipeFixture.detail(request)
            guard index < 2 else { return (data, response) }

            var body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            if index == 0 {
                body["state_version"] = 8
                return try SessionFixture.response(request, body: body, etag: #""state-8""#)
            }
            body["catalog_version"] = "other-catalog"
            return try SessionFixture.response(request, body: body, etag: #""state-7""#)
        }
        let model = try model(session, servings: 4, exclusions: ["milk"])
        await model.loadIfNeeded(for: model.context)
        let loaded = try snapshot(model)
        let card = try XCTUnwrap(loaded.items.first)
        let route = loaded.recipeRequest(for: card)

        for _ in 0..<2 {
            do {
                _ = try await model.repository.missingProducts(for: route, in: loaded.firstPage, count: 1)
                XCTFail("Expected recipe details from a different context to be rejected")
            } catch MissingProductsError.contextChanged {}
        }
        let names = try await model.repository.missingProducts(for: route, in: loaded.firstPage, count: 1)
        XCTAssertEqual(names, ["Рис"])

        let oldRequestID = loaded.firstPage.requestID
        await model.refreshSnapshot(requestID: oldRequestID)
        let refreshed = try snapshot(model)
        XCTAssertNotEqual(refreshed.firstPage.requestID, oldRequestID)
        XCTAssertEqual(refreshed.firstPage.stateVersion, 8)
        await model.refreshSnapshot(requestID: oldRequestID)
        let postRequests = await creations.requests
        XCTAssertEqual(postRequests.count, 2)
    }

    @MainActor
    func model(
        _ session: SessionStore, servings: Int = 2, exclusions: [String] = []
    ) throws -> ServerDishesModel {
        try ServerDishesModel(
            repository: RecommendationsRepository(session: session, account: XCTUnwrap(session.account)),
            initialContext: .init(advancedFilters: .init(excludedAllergenIDs: Set(exclusions)), servings: servings)
        )
    }

    @MainActor
    func snapshot(_ model: ServerDishesModel) throws -> DishesSnapshot {
        guard case .loaded(let snapshot) = model.phase else {
            XCTFail("Expected loaded snapshot")
            throw URLError(.cannotParseResponse)
        }
        return snapshot
    }
}
