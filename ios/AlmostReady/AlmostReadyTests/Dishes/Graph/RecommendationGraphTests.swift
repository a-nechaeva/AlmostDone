import Foundation
import XCTest

@testable import AlmostReady

final class RecommendationGraphTests: XCTestCase {
    @MainActor
    func testLoadsEntireGraphForTheVisiblePageAndPreservesServerAlternatives() async throws {
        let session = try await RecipeFixture.session { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(
                request.url?.absoluteString, "https://example.test/api/v1/recommendations/opaque%2Fsnapshot/graph")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer old-access")
            XCTAssertNil(request.httpBody)
            return try RecommendationGraphFixture.response(request)
        }
        let model = try model(session)
        let snapshot = try RecommendationGraphFixture.snapshot()
        guard case .loading = model.phase(for: snapshot) else { return XCTFail("Expected loading") }

        await model.loadIfNeeded(for: snapshot)
        let graph = try content(model, snapshot: snapshot)

        XCTAssertEqual(graph.homeTitle, "Дома")
        XCTAssertEqual(graph.homeDishes.map(\.request.id), ["ready"])
        XCTAssertEqual(graph.purchaseSets.map(\.id), ["rice-set", "milk-set", "both-set"])
        XCTAssertTrue(graph.hasUnrepresentedDishes)

        let rice = try XCTUnwrap(graph.purchaseSets.first)
        XCTAssertEqual(rice.cost?.minorUnits, 12_050)
        XCTAssertEqual(rice.dishes.map(\.request.id), ["rice", "rice-alternative"])
        XCTAssertEqual(rice.dishes.first?.card.suitability.status, .unknown)
        XCTAssertEqual(rice.dishes.first?.card.suitability.reasons.first?.message, "Состав не проверен")

        let both = try XCTUnwrap(graph.purchaseSets.last)
        XCTAssertEqual(both.dishes.map(\.request.id), ["both"])
        XCTAssertNil(both.cost)
        XCTAssertEqual(both.extensions.map(\.id), ["rice-set", "milk-set"])
        XCTAssertEqual(both.extensions.first?.items.map(\.packageCount), [2, 1])
        XCTAssertNil(both.extensions.first?.cost)
        XCTAssertEqual(both.extensions.last?.cost?.minorUnits, 36_150)

        var opened: RecipeRequest?
        var added: [ShoppingPackage] = []
        var addedRevision: AccountRevision?
        let view = RecommendationGraphView(
            phase: .loaded(graph), onRetry: {}, onRefreshSnapshot: {},
            onOpenRecipe: { opened = $0 },
            onAddSet: {
                added = $0
                addedRevision = $1
                return true
            }
        )
        try view.openRecipe(XCTUnwrap(rice.dishes.last))
        view.addSet(both, revision: graph.revision)
        XCTAssertEqual(
            opened, RecipeRequest(id: "rice-alternative", servings: 4, excludedAllergenIDs: ["eggs", "nuts"]))
        XCTAssertEqual(added.map(\.key), ["rice:standard", "milk:standard"])
        XCTAssertEqual(added.map(\.packageCount), [3, 1])
        XCTAssertNil(added.last?.totalPrice)
        XCTAssertEqual(addedRevision?.etag, #""state-7""#)
    }

    @MainActor
    func testHomeOnlyGraphCanBeEmpty() async throws {
        let session = try await RecipeFixture.session {
            try RecommendationGraphFixture.response($0, empty: true, unrepresented: false)
        }
        let model = try model(session)
        let snapshot = try RecommendationGraphFixture.snapshot()
        await model.loadIfNeeded(for: snapshot)
        let graph = try content(model, snapshot: snapshot)
        XCTAssertTrue(graph.isEmpty)
        XCTAssertFalse(graph.hasUnrepresentedDishes)
        XCTAssertTrue(graph.purchaseSets.isEmpty)
    }

    @MainActor
    func testNetworkErrorAndMismatchedResponseCanRetryTheSameSnapshot() async throws {
        let log = DishesRequestLog()
        let session = try await RecipeFixture.session { request in
            switch await log.append(request) {
            case 0: throw URLError(.notConnectedToInternet)
            case 1: return try RecommendationGraphFixture.response(request, id: "wrong")
            case 2: return try RecommendationGraphFixture.response(request, version: 6)
            case 3: return try RecommendationGraphFixture.response(request, requestID: UUID())
            case 4: return try RecommendationGraphFixture.response(request, etag: #""state-8""#)
            default: return try RecommendationGraphFixture.response(request)
            }
        }
        let model = try model(session)
        let snapshot = try RecommendationGraphFixture.snapshot()
        await model.loadIfNeeded(for: snapshot)
        for _ in 0..<5 {
            guard case .failed = model.phase(for: snapshot) else { return XCTFail("Expected a retryable error") }
            model.requestRetry(for: snapshot)
            await model.loadIfNeeded(for: snapshot)
        }
        XCTAssertFalse(try content(model, snapshot: snapshot).isEmpty)
        await model.loadIfNeeded(for: snapshot)
        let requests = await log.requests
        XCTAssertEqual(requests.count, 6)
        XCTAssertEqual(Set(requests.compactMap(\.url)).count, 1)
    }

    @MainActor
    func testUnavailableSnapshotRequiresRefreshingTheList() async throws {
        for (status, code) in [(409, "snapshot_expired"), (409, "context_changed"), (404, "not_found")] {
            let log = DishesRequestLog()
            let session = try await RecipeFixture.session { request in
                await log.append(request)
                return try SessionFixture.error(request, status: status, code: code)
            }
            let model = try model(session)
            let snapshot = try RecommendationGraphFixture.snapshot()
            await model.loadIfNeeded(for: snapshot)
            guard case .refreshSnapshot = model.phase(for: snapshot) else {
                return XCTFail("Expected a new list snapshot for \(code)")
            }
            model.requestRetry(for: snapshot)
            await model.loadIfNeeded(for: snapshot)
            let requests = await log.requests
            XCTAssertEqual(requests.count, 1)
        }
    }

    @MainActor
    func testCancelledRetryDoesNotPublishAndCanRestart() async throws {
        let started = SessionResponseGate()
        let release = SessionResponseGate()
        let log = DishesRequestLog()
        let session = try await RecipeFixture.session { request in
            switch await log.append(request) {
            case 0: throw URLError(.notConnectedToInternet)
            case 1:
                await started.open()
                await release.wait()
            default: break
            }
            return try RecommendationGraphFixture.response(request)
        }
        let model = try model(session)
        let snapshot = try RecommendationGraphFixture.snapshot()
        await model.loadIfNeeded(for: snapshot)
        model.requestRetry(for: snapshot)
        let retry = model.retryAttempt
        let task = Task { await model.loadIfNeeded(for: snapshot, retryAttempt: retry) }
        await started.wait()
        task.cancel()
        await release.open()
        await task.value
        guard case .loading = model.phase(for: snapshot) else { return XCTFail("Cancelled result became visible") }

        await model.loadIfNeeded(for: snapshot)
        XCTAssertFalse(try content(model, snapshot: snapshot).isEmpty)
    }

    @MainActor
    func testLateOldGraphDoesNotReplaceGraphForTheNewSnapshot() async throws {
        let started = SessionResponseGate()
        let release = SessionResponseGate()
        let old = try RecommendationGraphFixture.snapshot(id: "old")
        let new = try RecommendationGraphFixture.snapshot(id: "new")
        let session = try await RecipeFixture.session { request in
            if request.url?.path == "/api/v1/recommendations/old/graph" {
                await started.open()
                await release.wait()
                return try RecommendationGraphFixture.response(request, id: "old")
            }
            return try RecommendationGraphFixture.response(request, id: "new", empty: true)
        }
        let model = try model(session)
        let task = Task { await model.loadIfNeeded(for: old) }
        await started.wait()
        model.reset()
        await model.loadIfNeeded(for: new)
        await release.open()
        await task.value

        XCTAssertTrue(try content(model, snapshot: new).isEmpty)
        guard case .loading = model.phase(for: old) else { return XCTFail("The old graph was published") }
    }

    @MainActor
    func testPantryChangeHidesLoadedGraph() async throws {
        let session = try await RecipeFixture.session { request in
            switch request.httpMethod {
            case "DELETE":
                return try SessionFixture.response(
                    request, body: ["state_version": 8, "items": []], etag: #""state-8""#)
            default:
                return try RecommendationGraphFixture.response(request)
            }
        }
        let model = try model(session)
        let snapshot = try RecommendationGraphFixture.snapshot()
        await model.loadIfNeeded(for: snapshot)
        XCTAssertFalse(try content(model, snapshot: snapshot).isEmpty)

        let repository = ProductsRepository(session: session, account: try XCTUnwrap(session.account))
        _ = try await repository.write(.delete(ingredientID: "rice"), basedOn: XCTUnwrap(session.revision))
        guard case .loading = model.phase(for: snapshot) else { return XCTFail("Graph survived a pantry revision") }
    }

    @MainActor
    func testSignOutHidesLoadedGraph() async throws {
        let session = try await RecipeFixture.session { request in
            if request.url?.path == "/api/v1/auth/logout" {
                return try SessionFixture.response(request, status: 204)
            }
            return try RecommendationGraphFixture.response(request)
        }
        let model = try model(session)
        let snapshot = try RecommendationGraphFixture.snapshot()
        await model.loadIfNeeded(for: snapshot)
        XCTAssertFalse(try content(model, snapshot: snapshot).isEmpty)

        _ = try await session.signOut()
        guard case .loading = model.phase(for: snapshot) else { return XCTFail("Graph survived sign-out") }
    }

    @MainActor
    func testReadyDishesRemainAvailableWhenThereAreNoPurchaseSets() async throws {
        let session = try await RecipeFixture.session {
            try RecommendationGraphFixture.response($0, readyOnly: true, unrepresented: false)
        }
        let model = try model(session)
        let snapshot = try RecommendationGraphFixture.snapshot()
        await model.loadIfNeeded(for: snapshot)
        let graph = try content(model, snapshot: snapshot)

        XCTAssertFalse(graph.isEmpty)
        XCTAssertEqual(graph.homeDishes.map(\.request.id), ["ready"])
        XCTAssertTrue(graph.purchaseSets.isEmpty)
    }

    @MainActor
    func testRefreshingExpiredGraphReplacesTheSharedSnapshotAndKeepsGraphMode() async throws {
        let log = DishesRequestLog()
        let creations = DishesRequestLog()
        let session = try await RecipeFixture.session { request in
            await log.append(request)
            if request.httpMethod == "POST" {
                let index = await creations.append(request)
                return try DishesFixture.page(
                    request, snapshotID: index == 0 ? "expired" : "fresh",
                    items: [DishesFixture.card(index == 0 ? "old" : "ready", servings: 4)]
                )
            }
            if request.url?.path == "/api/v1/recommendations/expired/graph" {
                return try SessionFixture.error(request, status: 409, code: "snapshot_expired")
            }
            XCTAssertEqual(request.url?.path, "/api/v1/recommendations/fresh/graph")
            let requests = await creations.requests
            let creation = try XCTUnwrap(requests.last)
            let body = try DishesFixture.body(creation)
            let requestID = try XCTUnwrap((body["request_id"] as? String).flatMap(UUID.init(uuidString:)))
            let filters = try XCTUnwrap(body["filters"] as? [String: Any])
            return try RecommendationGraphFixture.response(
                request, id: "fresh", readyOnly: true, requestID: requestID, filters: filters
            )
        }
        let repository = try RecommendationsRepository(session: session, account: XCTUnwrap(session.account))
        let dishes = ServerDishesModel(repository: repository, initialContext: RecommendationGraphFixture.context)
        await dishes.loadIfNeeded(for: dishes.context)
        let expired = try XCTUnwrap(dishes.graphSnapshot)
        XCTAssertEqual(expired.id, "expired")
        dishes.resultsMode = .graph
        await dishes.graph.loadIfNeeded(for: expired)
        guard case .refreshSnapshot = dishes.graph.phase(for: expired) else {
            return XCTFail("Expected graph to refresh the list snapshot")
        }
        await dishes.refreshSnapshot(requestID: expired.requestID)
        let fresh = try XCTUnwrap(dishes.graphSnapshot)
        XCTAssertEqual(fresh.id, "fresh")
        XCTAssertNotEqual(fresh.requestID, expired.requestID)
        XCTAssertEqual(dishes.resultsMode, .graph)
        await dishes.graph.loadIfNeeded(for: fresh)
        let graph = try content(dishes.graph, snapshot: fresh)
        XCTAssertEqual(graph.homeDishes.first?.request.excludedAllergenIDs, ["eggs", "nuts"])
        dishes.resultsMode = .list
        guard case .loaded(let list) = dishes.phase else { return XCTFail("Expected the refreshed list") }
        XCTAssertEqual(list.items.map(\.id), ["ready"])
        XCTAssertEqual(list.firstPage.snapshotID, fresh.id)
        dishes.resultsMode = .graph
        await dishes.graph.loadIfNeeded(for: fresh)
        let requests = await log.requests
        XCTAssertEqual(
            requests.compactMap { $0.url?.path },
            [
                "/api/v1/recommendations", "/api/v1/recommendations/expired/graph",
                "/api/v1/recommendations", "/api/v1/recommendations/fresh/graph"
            ]
        )
    }

    @MainActor
    func testAlreadyExpiredGraphResponseCannotBeUsed() async throws {
        let session = try await RecipeFixture.session {
            try RecommendationGraphFixture.response($0, expiresAt: .now.addingTimeInterval(-1))
        }
        let model = try model(session)
        let snapshot = try RecommendationGraphFixture.snapshot()
        await model.loadIfNeeded(for: snapshot)
        guard case .refreshSnapshot = model.phase(for: snapshot) else {
            return XCTFail("Expired graph content became actionable")
        }
    }

    @MainActor
    func testRecipeReadWithNewerRevisionMakesCachedGraphRefreshable() async throws {
        let session = try await RecipeFixture.session { request in
            if request.url?.path == RecipeFixture.detailPath {
                return try RecipeFixture.detail(request, stateVersion: 8)
            }
            return try RecommendationGraphFixture.response(request, readyOnly: true)
        }
        let model = try model(session)
        let snapshot = try RecommendationGraphFixture.snapshot()
        await model.loadIfNeeded(for: snapshot)
        XCTAssertTrue(try content(model, snapshot: snapshot).purchaseSets.isEmpty)
        let recipe = try RecipeFixture.model(session)
        await recipe.load(attempt: recipe.attempt)
        XCTAssertEqual(session.shoppingRevision?.stateVersion, 8)
        guard case .refreshSnapshot = model.phase(for: snapshot) else {
            return XCTFail("The old graph is still actionable after a newer recipe read")
        }
    }

    @MainActor
    func testGraphAcceptsServerRoundingOfKcalFilter() async throws {
        var context = RecommendationGraphFixture.context
        context.advancedFilters.maxKcalPerServing = Decimal(string: "450.1234567890123456")
        let snapshot = try RecommendationGraphFixture.snapshot(context: context)
        let session = try await RecipeFixture.session { request in
            try RecommendationGraphFixture.response(
                request,
                filters: [
                    "q": "обед", "mode": "all", "max_minutes": 30, "max_kcal_per_serving": 450.1234567890123,
                    "equipment": ["stove", "no_cook"], "exclude_allergens": ["eggs", "nuts"]
                ])
        }
        let model = try model(session)
        await model.loadIfNeeded(for: snapshot)
        XCTAssertFalse(try content(model, snapshot: snapshot).isEmpty)
    }

    @MainActor
    private func model(_ session: SessionStore) throws -> RecommendationGraphModel {
        let repository = try RecommendationsRepository(session: session, account: XCTUnwrap(session.account))
        return RecommendationGraphModel(repository: repository)
    }

    @MainActor
    private func content(
        _ model: RecommendationGraphModel, snapshot: RecommendationGraphSnapshot
    ) throws -> RecommendationGraphContent {
        guard case .loaded(let content) = model.phase(for: snapshot) else {
            XCTFail("Expected a loaded graph")
            throw URLError(.cannotParseResponse)
        }
        return content
    }
}
