import Foundation
import XCTest

@testable import AlmostReady

final class FavoritesTests: XCTestCase {
    private typealias Fixture = SessionFixture
    private static let recipesPath = "/api/v1/me/favorites/recipes"
    private static let ingredientsPath = "/api/v1/me/favorites/ingredients"

    @MainActor
    func testBothCategoriesConfirmAddAndRemoveOnTheSharedStore() async throws {
        let requests = FavoritesRequestLog()
        let store = try await restoredStore { request in
            let index = await requests.append(request)
            switch index {
            case 1:
                return try Self.page(request, version: 7, entries: [])
            case 2:
                return try Self.mutation(request, version: 8)
            case 3:
                return try Self.mutation(request, version: 9)
            case 4:
                return try Self.page(request, version: 9, entries: [])
            case 5:
                return try Self.mutation(request, version: 10)
            case 6:
                return try Self.mutation(request, version: 11)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        for (category, id, name) in [
            (FavoritesCategory.recipes, "dish/one", "Омлет"),
            (.ingredients, "cheese/aged", "Сыр")
        ] {
            await store.load(category)
            let entry = FavoriteEntry(id: id, name: name)
            let before = store.state(for: category)
            XCTAssertNotNil(before.snapshot)
            XCTAssertFalse(before.contains(id))
            await store.set(.init(entry: entry, isFavorite: true), in: category)
            let after = store.state(for: category)
            XCTAssertTrue(after.contains(id))
            XCTAssertEqual(after.snapshot?.entries, [entry])
            await store.set(.init(entry: entry, isFavorite: false), in: category)
            XCTAssertFalse(store.state(for: category).contains(id))
            XCTAssertEqual(store.state(for: category).snapshot?.entries, [])
        }
        XCTAssertEqual(store.repository.session.revision?.stateVersion, 11)

        let sent = await requests.values
        XCTAssertEqual(sent.map(\.httpMethod), ["GET", "PUT", "DELETE", "GET", "PUT", "DELETE"])
        XCTAssertEqual(
            sent.map { $0.url?.absoluteString },
            [
                "https://example.test" + Self.recipesPath,
                "https://example.test" + Self.recipesPath + "/dish%2Fone",
                "https://example.test" + Self.recipesPath + "/dish%2Fone",
                "https://example.test" + Self.ingredientsPath,
                "https://example.test" + Self.ingredientsPath + "/cheese%2Faged",
                "https://example.test" + Self.ingredientsPath + "/cheese%2Faged"
            ])
        XCTAssertEqual(
            sent.map { $0.value(forHTTPHeaderField: "If-Match") },
            [
                nil, Self.etag(7), Self.etag(8), nil, Self.etag(9), Self.etag(10)
            ])
        for request in sent {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer old-access")
            XCTAssertNil(request.value(forHTTPHeaderField: "Idempotency-Key"))
            XCTAssertNil(request.httpBody)
        }
    }

    @MainActor
    func testPaginationRestartsWhenTheServerInvalidatesTheCursor() async throws {
        let requests = FavoritesRequestLog()
        let store = try await restoredStore { request in
            XCTAssertEqual(request.url?.path, Self.ingredientsPath)
            switch await requests.append(request) {
            case 1:
                return try Self.page(request, version: 7, entries: [Self.ingredient("old")], cursor: "old+cursor")
            case 2:
                return try Fixture.error(request, status: 409, code: "context_changed")
            case 3:
                return try Self.page(request, version: 8, entries: [Self.ingredient("cheese")], cursor: "new+cursor")
            case 4:
                return try Self.page(request, version: 8, entries: [Self.ingredient("tomato")])
            default:
                throw URLError(.unsupportedURL)
            }
        }
        await store.load(.ingredients)
        let state = store.state(for: .ingredients)
        XCTAssertEqual(state.snapshot?.entries.map(\.id), ["cheese", "tomato"])
        XCTAssertEqual(state.snapshot?.entries.first?.allowedUnits, [.grams])
        XCTAssertEqual(state.snapshot?.revision.stateVersion, 8)
        let sent = await requests.values
        XCTAssertEqual(
            sent.map { $0.url?.query(percentEncoded: true) }, [nil, "cursor=old%2Bcursor", nil, "cursor=new%2Bcursor"])
    }

    @MainActor
    func testNewerRevisionInOneCategoryInvalidatesTheOtherCategoryCache() async throws {
        let requests = FavoritesRequestLog()
        let store = try await restoredStore { request in
            switch await requests.append(request) {
            case 1: return try Self.page(request, version: 7, entries: [Self.recipe("old")])
            case 2: return try Self.page(request, version: 8, entries: [Self.ingredient("cheese")])
            case 3: return try Self.page(request, version: 8, entries: [])
            default: throw URLError(.unsupportedURL)
            }
        }

        await store.load(.recipes)
        XCTAssertTrue(store.state(for: .recipes).contains("old"))
        await store.load(.ingredients)
        await store.load(.recipes)
        XCTAssertEqual(store.state(for: .recipes).snapshot?.entries, [])
        let sent = await requests.values
        XCTAssertEqual(sent.map { $0.url?.path }, [Self.recipesPath, Self.ingredientsPath, Self.recipesPath])
    }

    @MainActor
    func testConflictRereadsStateAndListThenRetriesTheSameIntent() async throws {
        let requests = FavoritesRequestLog()
        let session = try Fixture.store(storage: SessionTestStorage(.active(Fixture.original))) { request in
            switch await requests.append(request) {
            case 1: return try Fixture.stateResponse(request)
            case 2: return try Self.page(request, version: 7, entries: [Self.recipe("dish")])
            case 3: return try Fixture.error(request, status: 412, code: "state_conflict")
            case 4: return try Fixture.stateResponse(request, version: 8)
            case 5: return try Self.page(request, version: 8, entries: [Self.recipe("dish"), Self.recipe("new")])
            case 6: return try Self.mutation(request, version: 9)
            default: throw URLError(.unsupportedURL)
            }
        }
        await session.restore()
        let store = FavoritesStore(session: session, account: try XCTUnwrap(session.account))
        await store.load(.recipes)
        let entry = try XCTUnwrap(store.state(for: .recipes).snapshot?.entries.first)
        await store.set(.init(entry: entry, isFavorite: false), in: .recipes)

        let sent = await requests.values
        XCTAssertEqual(sent.map(\.httpMethod), ["GET", "GET", "DELETE", "GET", "GET", "DELETE"])
        XCTAssertEqual(
            sent.map { $0.url?.path },
            [
                "/api/v1/me/state", Self.recipesPath, Self.recipesPath + "/dish",
                "/api/v1/me/state", Self.recipesPath, Self.recipesPath + "/dish"
            ])
        XCTAssertEqual(
            sent.map { $0.value(forHTTPHeaderField: "If-Match") },
            [
                nil, nil, Self.etag(7), nil, nil, Self.etag(8)
            ])
        let state = store.state(for: .recipes)
        XCTAssertEqual(state.snapshot?.entries.map(\.id), ["new"])
        XCTAssertNil(state.failedChange)
        XCTAssertEqual(session.revision?.stateVersion, 9)
    }

    @MainActor
    func testLoadAndWriteErrorsKeepConfirmedMembershipAndRetryTheOriginalTarget() async throws {
        let requests = FavoritesRequestLog()
        let store = try await restoredStore { request in
            switch await requests.append(request) {
            case 1, 3: return try Fixture.error(request, status: 503, code: "service_unavailable")
            case 2: return try Self.page(request, version: 7, entries: [Self.ingredient("cheese")])
            case 4: return try Self.mutation(request, version: 8)
            default: throw URLError(.unsupportedURL)
            }
        }
        await store.load(.ingredients)
        XCTAssertTrue(store.state(for: .ingredients).loadFailed)
        XCTAssertNil(store.state(for: .ingredients).snapshot)
        await store.load(.ingredients, force: true)
        XCTAssertFalse(store.state(for: .ingredients).loadFailed)
        let entry = try XCTUnwrap(store.state(for: .ingredients).snapshot?.entries.first)

        await store.set(.init(entry: entry, isFavorite: false), in: .ingredients)
        XCTAssertTrue(store.state(for: .ingredients).contains(entry.id))
        let retry = try XCTUnwrap(store.state(for: .ingredients).failedChange)
        XCTAssertFalse(retry.isFavorite)
        await store.set(retry, in: .ingredients)
        XCTAssertFalse(store.state(for: .ingredients).contains(entry.id))
        XCTAssertNil(store.state(for: .ingredients).failedChange)

        let sent = await requests.values
        XCTAssertEqual(sent.map(\.httpMethod), ["GET", "GET", "DELETE", "DELETE"])
        XCTAssertEqual(
            sent.suffix(2).map { $0.url?.path }, Array(repeating: Self.ingredientsPath + "/cheese", count: 2))
    }

    @MainActor
    func testSwitchingAccountDropsCachedFavoritesAndIgnoresALateMutation() async throws {
        let mutationStarted = expectation(description: "Previous account mutation reached transport")
        let finishMutation = SessionResponseGate()
        let storage = SessionTestStorage(.active(Fixture.original))
        let session = try Fixture.store(storage: storage) { request in
            let isOriginal = request.value(forHTTPHeaderField: "Authorization") == "Bearer old-access"
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/v1/me/state"):
                return try Fixture.stateResponse(request, user: isOriginal ? Fixture.original : Fixture.another)
            case ("GET", Self.recipesPath):
                return try Self.page(request, version: 7, entries: [Self.recipe(isOriginal ? "old" : "new")])
            case ("DELETE", Self.recipesPath + "/old"):
                mutationStarted.fulfill()
                await finishMutation.wait()
                return try Self.mutation(request, version: 8)
            case ("POST", "/api/v1/auth/logout"):
                return try Fixture.response(request, status: 204)
            case ("POST", "/api/v1/auth/yandex"):
                return try Fixture.sessionResponse(request, Fixture.another)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        await session.restore()
        let old = FavoritesStore(session: session, account: try XCTUnwrap(session.account))
        await old.load(.recipes)
        let entry = try XCTUnwrap(old.state(for: .recipes).snapshot?.entries.first)
        let deletion = Task { await old.set(.init(entry: entry, isFavorite: false), in: .recipes) }
        await fulfillment(of: [mutationStarted], timeout: 5)
        XCTAssertTrue(old.state(for: .recipes).contains("old"))
        _ = try await session.signOut()
        XCTAssertNil(old.state(for: .recipes).snapshot)

        await session.signIn()
        let current = FavoritesStore(session: session, account: try XCTUnwrap(session.account))
        await current.load(.recipes)
        await finishMutation.open()
        await deletion.value

        XCTAssertEqual(current.state(for: .recipes).snapshot?.entries.map(\.id), ["new"])
        XCTAssertNil(old.state(for: .recipes).snapshot)
        XCTAssertNil(old.state(for: .recipes).failedChange)
        XCTAssertEqual(session.revision?.stateVersion, 7)
    }

    @MainActor
    func testPantryAddWithNullSurvivesClosingFavoritesAndRetriesFailedRefresh() async throws {
        let requests = FavoritesRequestLog()
        let store = try await restoredStore { request in
            switch await requests.append(request) {
            case 1:
                return try Self.page(request, version: 7, entries: [Self.ingredient("cheese/aged")])
            case 2:
                return try Self.pantry(request, version: 7, items: [])
            case 3, 5:
                throw URLError(.timedOut)
            case 4, 6:
                return try Self.pantry(
                    request, version: 8,
                    items: [["ingredient_id": "cheese/aged", "name": "Сыр", "quantity": NSNull()]]
                )
            default:
                throw URLError(.unsupportedURL)
            }
        }
        await store.load(.ingredients)
        let entry = try XCTUnwrap(store.state(for: .ingredients).snapshot?.entries.first)
        let prepared = await store.preparePantryDraft(for: entry)
        XCTAssertTrue(prepared)
        let draft = try XCTUnwrap(store.pantryDraft)
        XCTAssertEqual(draft.allowedUnits, [.grams])

        let first = await store.pantry.save(draft)
        XCTAssertFalse(first)
        XCTAssertTrue(draft.hasPendingAdd)
        store.dismissPantryDraft()
        let overwritten = await store.preparePantryDraft(for: entry)
        XCTAssertFalse(overwritten)
        let resumed = try XCTUnwrap(store.pantryDraft)
        XCTAssertTrue(resumed === draft)
        let retry = await store.pantry.save(resumed)
        XCTAssertTrue(retry)
        let item = try XCTUnwrap(store.pantry.snapshot?.items.first)
        XCTAssertEqual(item.id, entry.id)
        XCTAssertNil(item.quantity)
        XCTAssertTrue(store.state(for: .ingredients).contains(entry.id))
        XCTAssertTrue(store.pantry.loadFailed)
        store.dismissPantryDraft()
        XCTAssertNil(store.pantryDraft)
        let preparedAgain = await store.preparePantryDraft(for: entry)
        XCTAssertTrue(preparedAgain)
        XCTAssertFalse(store.pantry.loadFailed)

        let sent = await requests.values
        XCTAssertEqual(sent.map(\.httpMethod), ["GET", "GET", "POST", "POST", "GET", "GET"])
        let adds = sent.filter { $0.url?.path == "/api/v1/me/pantry/add" }
        XCTAssertEqual(adds.count, 2)
        let keys = adds.compactMap { $0.value(forHTTPHeaderField: "Idempotency-Key") }
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(Set(keys).count, 1)
        XCTAssertNotNil(keys.first.flatMap { UUID(uuidString: $0) })
        for request in adds {
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), Self.etag(7))
            let json = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody))
            let body = try XCTUnwrap(json as? [String: Any])
            XCTAssertEqual(body["ingredient_id"] as? String, entry.id)
            XCTAssertTrue(body["quantity"] is NSNull)
        }
    }

    @MainActor
    func testPantryAddWithQuantityUsesTheFavoriteIngredientAndItsUnit() async throws {
        let store = try await restoredStore { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", Self.ingredientsPath):
                return try Self.page(request, version: 7, entries: [Self.ingredient("cheese")])
            case ("GET", "/api/v1/me/pantry"):
                return try Self.pantry(request, version: 7, items: [])
            case ("POST", "/api/v1/me/pantry/add"):
                let body = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
                )
                let quantity = try XCTUnwrap(body["quantity"] as? [String: Any])
                XCTAssertEqual(body["ingredient_id"] as? String, "cheese")
                XCTAssertEqual(quantity["value"] as? Double, 12.5)
                XCTAssertEqual(quantity["unit"] as? String, "g")
                return try Self.pantry(
                    request, version: 8,
                    items: [["ingredient_id": "cheese", "name": "Сыр", "quantity": ["value": 12.5, "unit": "g"]]]
                )
            default:
                throw URLError(.unsupportedURL)
            }
        }
        await store.load(.ingredients)
        let entry = try XCTUnwrap(store.state(for: .ingredients).snapshot?.entries.first)
        let prepared = await store.preparePantryDraft(for: entry)
        XCTAssertTrue(prepared)
        let draft = try XCTUnwrap(store.pantryDraft)
        draft.quantityText = "12,5"
        let saved = await store.pantry.save(draft)
        XCTAssertTrue(saved)
        XCTAssertEqual(store.pantry.snapshot?.items.first?.quantity, PantryQuantity(value: 12.5, unit: .grams))
    }

    @MainActor
    private func restoredStore(
        _ respond: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) async throws -> FavoritesStore {
        let session = try Fixture.store(storage: SessionTestStorage(.active(Fixture.original))) { request in
            if request.url?.path == "/api/v1/me/state" { return try Fixture.stateResponse(request) }
            return try await respond(request)
        }
        await session.restore()
        return FavoritesStore(session: session, account: try XCTUnwrap(session.account))
    }

    private static func recipe(_ id: String) -> [String: Any] {
        [
            "id": id, "title": "Омлет", "photo_url": NSNull(), "servings": 2, "minutes": NSNull(),
            "nutrition_per_serving": NSNull(), "nutrition_source": NSNull(), "buy_cost": NSNull(),
            "availability": ["status": "unknown", "missing_count": 0, "unknown_quantity_ids": []] as [String: Any],
            "suitability": ["status": "unknown", "reasons": []] as [String: Any],
            "allergens": allergens,
            "is_favorite": true, "methods": ["stove"]
        ]
    }

    private static func ingredient(_ id: String) -> [String: Any] {
        [
            "id": id, "name": "Сыр", "allowed_units": ["g"], "nutrition_per_100g": NSNull(),
            "allergens": allergens, "offers": [], "is_favorite": true
        ]
    }

    private static var allergens: [String: Any] {
        ["contains": [], "completeness": "unknown", "sources": []]
    }

    private static func page(
        _ request: URLRequest, version: Int, entries: [[String: Any]], cursor: String? = nil
    ) throws -> (Data, URLResponse) {
        var body: [String: Any] = [
            "state_version": version,
            "items": entries,
            "page": ["has_more": cursor != nil, "next_cursor": cursor.map { $0 as Any } ?? NSNull()]
        ]
        if request.url?.path == ingredientsPath {
            body["catalog_version"] = "fixture-catalog"
        }
        return try Fixture.response(request, body: body, etag: etag(version))
    }

    private static func mutation(_ request: URLRequest, version: Int) throws -> (Data, URLResponse) {
        try Fixture.response(request, body: ["state_version": version], etag: etag(version))
    }

    private static func pantry(_ request: URLRequest, version: Int, items: [[String: Any]]) throws -> (
        Data, URLResponse
    ) {
        try Fixture.response(request, body: ["state_version": version, "items": items], etag: etag(version))
    }

    private static func etag(_ version: Int) -> String {
        #""state-\#(version)""#
    }
}

private actor FavoritesRequestLog {
    private(set) var values: [URLRequest] = []

    func append(_ request: URLRequest) -> Int {
        values.append(request)
        return values.count
    }
}
