import Foundation
import XCTest

@testable import AlmostReady

@MainActor
final class ShoppingAPITests: XCTestCase {
    func testBothRecommendationRequestsUseBudgetInKopecksAndCurrentContext() async throws {
        let requests = ShoppingRequestLog()
        let (model, _) = try await makeModel { request in
            if request.url?.path == ShoppingFixture.state { return try SessionFixture.stateResponse(request) }
            _ = await requests.record(request)
            return try ShoppingFixture.recommendation(request)
        }
        model.budgetInput = " 1 000,05 "
        model.servings = 3
        model.filters = ShoppingFilters(
            query: "сыр", mode: "buy_1_3", maxMinutes: 20, maxKcalPerServing: 450,
            equipment: ["stove", "no_cook"], excludeAllergens: ["nuts"]
        )

        await model.loadRecommendation(.singlePurchase)
        let single = try result(model)
        XCTAssertEqual(single.status, .found)
        XCTAssertEqual(single.suggestions.map(\.unlockedRecipeCount), [2, 1])
        XCTAssertEqual(single.suggestions.map { $0.totalCost?.minorUnits }, [46_000, 9_500])
        XCTAssertEqual(single.suggestions.first?.items.first?.packageQuantity.value, 200)
        XCTAssertEqual(single.suggestions.first?.items.first?.packageCount, 2)

        model.filters = ShoppingFilters()
        await model.loadRecommendation(.budget)
        let budget = try result(model)
        XCTAssertEqual(budget.status, .found)
        XCTAssertEqual(budget.suggestions.first?.totalCost?.minorUnits, 55_500)
        XCTAssertEqual(budget.suggestions.first?.items.map(\.ingredientID), ["cheese", "milk"])

        let sent = await requests.all
        XCTAssertEqual(sent.compactMap { $0.url?.path }, [ShoppingFixture.single, ShoppingFixture.budget])
        let purchaseBodies = try sent.map { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer old-access")
            XCTAssertNil(request.value(forHTTPHeaderField: "If-Match"))
            let body = try ShoppingFixture.json(request)
            XCTAssertEqual(Set(body.keys), ["request_id", "servings", "filters", "budget"])
            XCTAssertEqual(body["servings"] as? Int, 3)
            let money = try XCTUnwrap(body["budget"] as? [String: Any])
            XCTAssertEqual(money["minor_units"] as? Int, 100_005)
            XCTAssertEqual(money["currency"] as? String, "RUB")
            return body
        }
        let requestIDs = purchaseBodies.compactMap { ($0["request_id"] as? String).flatMap(UUID.init(uuidString:)) }
        XCTAssertEqual(Set(requestIDs).count, 2)
        let first = try XCTUnwrap(purchaseBodies.first)
        let second = try XCTUnwrap(purchaseBodies.dropFirst().first)
        let filters = try XCTUnwrap(first["filters"] as? [String: Any])
        XCTAssertEqual(filters["q"] as? String, "сыр")
        XCTAssertEqual(filters["mode"] as? String, "buy_1_3")
        XCTAssertEqual(filters["max_minutes"] as? Int, 20)
        XCTAssertEqual(filters["max_kcal_per_serving"] as? Int, 450)
        XCTAssertEqual(filters["equipment"] as? [String], ["stove", "no_cook"])
        XCTAssertEqual(filters["exclude_allergens"] as? [String], ["nuts"])
        let defaults = try XCTUnwrap(second["filters"] as? [String: Any])
        XCTAssertEqual(defaults["q"] as? String, "")
        XCTAssertEqual(defaults["mode"] as? String, "all")
        XCTAssertTrue(defaults["max_minutes"] is NSNull)
        XCTAssertTrue(defaults["max_kcal_per_serving"] is NSNull)
        XCTAssertEqual(defaults["equipment"] as? [String], ["stove", "oven", "microwave", "no_cook"])
        XCTAssertEqual(defaults["exclude_allergens"] as? [String], [])
    }

    func testInvalidBudgetStaysInDraftAndDoesNotSendRequests() async throws {
        let (model, _) = try await makeModel { request in
            XCTAssertEqual(request.url?.path, ShoppingFixture.state)
            return try SessionFixture.stateResponse(request)
        }
        let invalid: [(String, ShoppingBudgetError)] = [
            ("", .empty), ("-1", .invalid), ("5,001", .invalid), ("92233720368547759", .invalid)
        ]
        for (input, expectedError) in invalid {
            model.budgetInput = input
            await model.loadRecommendation(.budget)
            guard case .invalidBudget(let error) = model.recommendation else {
                return XCTFail("Expected invalid budget for \(input)")
            }
            XCTAssertEqual(error, expectedError)
            XCTAssertEqual(model.budgetInput, input)
        }
    }

    func testNoPlanInsufficientDataAnd503AreDistinctAndCanRetry() async throws {
        let requests = ShoppingRequestLog()
        let (model, _) = try await makeModel { request in
            if request.url?.path == ShoppingFixture.state { return try SessionFixture.stateResponse(request) }
            switch await requests.record(request) {
            case 1:
                return try ShoppingFixture.recommendation(request, status: "no_plan")
            case 2:
                return try ShoppingFixture.recommendation(request, status: "insufficient_data")
            case 3:
                return try SessionFixture.error(request, status: 503, code: "service_unavailable")
            default:
                return try ShoppingFixture.recommendation(request)
            }
        }

        model.budgetInput = "0"
        await model.loadRecommendation(.budget)
        let noPlan = try result(model)
        XCTAssertEqual(noPlan.status, .noPlan)
        XCTAssertTrue(noPlan.suggestions.isEmpty)
        XCTAssertFalse(noPlan.hasUnpricedRecipes)

        model.budgetInput = "500"
        await model.loadRecommendation(.singlePurchase)
        let insufficientData = try result(model)
        XCTAssertEqual(insufficientData.status, .insufficientData)
        XCTAssertTrue(insufficientData.suggestions.isEmpty)
        XCTAssertTrue(insufficientData.hasUnpricedRecipes)

        model.budgetInput = "777,50"
        await model.loadRecommendation(.budget)
        guard case .unavailable = model.recommendation else { return XCTFail("Expected a retryable failure") }
        XCTAssertEqual(model.budgetInput, "777,50")
        await model.loadRecommendation(.budget)
        XCTAssertEqual(try result(model).status, .found)
        let sent = await requests.all
        let noPlanRequest = try XCTUnwrap(sent.first)
        let zeroBudget = try XCTUnwrap(ShoppingFixture.json(noPlanRequest)["budget"] as? [String: Any])
        XCTAssertEqual(zeroBudget["minor_units"] as? Int, 0)
        for request in sent.suffix(2) {
            let money = try XCTUnwrap(ShoppingFixture.json(request)["budget"] as? [String: Any])
            XCTAssertEqual(money["minor_units"] as? Int, 77_750)
        }
    }

    func testLateResponseForEditedBudgetCannotReplaceNewResult() async throws {
        let started = SessionResponseGate()
        let release = SessionResponseGate()
        let requests = ShoppingRequestLog()
        let (model, _) = try await makeModel { request in
            if request.url?.path == ShoppingFixture.state { return try SessionFixture.stateResponse(request) }
            if await requests.record(request) == 1 {
                await started.open()
                await release.wait()
                return try ShoppingFixture.recommendation(request, status: "no_plan")
            }
            return try ShoppingFixture.recommendation(request)
        }

        let earlier = Task { await model.loadRecommendation(.budget) }
        await started.wait()
        model.budgetInput = "650"
        let currentID = await model.loadRecommendation(.budget)
        await release.open()
        let outdatedID = await earlier.value

        XCTAssertNil(outdatedID)
        XCTAssertTrue(model.isCurrentRecommendation(try XCTUnwrap(currentID)))
        XCTAssertEqual(model.budgetInput, "650")
        XCTAssertEqual(try result(model).status, .found)
    }

    func testLateResponseForPreviousFiltersAndPortionsIsDiscarded() async throws {
        let started = SessionResponseGate()
        let release = SessionResponseGate()
        let (model, _) = try await makeModel { request in
            if request.url?.path == ShoppingFixture.state { return try SessionFixture.stateResponse(request) }
            await started.open()
            await release.wait()
            return try ShoppingFixture.recommendation(request)
        }

        let earlier = Task { await model.loadRecommendation(.singlePurchase) }
        await started.wait()
        model.filters.mode = "now"
        model.servings = 4
        await release.open()
        let outdatedID = await earlier.value

        XCTAssertNil(outdatedID)
        guard case .idle = model.recommendation else { return XCTFail("Old context was displayed") }
    }

    func testLateResponseAfterAccountRevisionChangesIsDiscarded() async throws {
        let started = SessionResponseGate()
        let release = SessionResponseGate()
        let states = ShoppingRequestLog()
        let (model, session) = try await makeModel { request in
            if request.url?.path == ShoppingFixture.state {
                let count = await states.record(request)
                return try SessionFixture.stateResponse(request, version: count == 1 ? 7 : 8)
            }
            await started.open()
            await release.wait()
            return try ShoppingFixture.recommendation(request)
        }

        let earlier = Task { await model.loadRecommendation(.singlePurchase) }
        await started.wait()
        let account = try XCTUnwrap(session.account)
        let updated = try await session.reloadRevision(for: account)
        XCTAssertEqual(updated.stateVersion, 8)
        await release.open()
        let outdatedID = await earlier.value

        XCTAssertNil(outdatedID)
        guard case .idle = model.recommendation else { return XCTFail("Old revision was displayed") }
    }

    func testLocalMarkDoesNotWriteAndExplicitTransferUsesPackageQuantitiesAndSnapshotETag() async throws {
        let requests = ShoppingRequestLog()
        let (model, session) = try await makeModel { request in
            switch request.url?.path {
            case ShoppingFixture.state:
                return try SessionFixture.stateResponse(request)
            case ShoppingFixture.budget:
                return try ShoppingFixture.recommendation(request, version: 8)
            default:
                _ = await requests.record(request)
                return try ShoppingFixture.mutation(request, version: 9)
            }
        }

        try await addBudget(model)
        XCTAssertEqual(session.revision?.stateVersion, 7)
        for item in model.items { _ = model.setPurchased(true, id: item.id) }
        XCTAssertEqual(model.markedCount, 2)
        let beforeConfirmation = await requests.all
        XCTAssertTrue(beforeConfirmation.isEmpty)

        await model.confirmTransfer()

        let sent = await requests.all
        XCTAssertEqual(sent.count, 1)
        let request = try XCTUnwrap(sent.first)
        XCTAssertEqual(request.url?.path, ShoppingFixture.purchased)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer old-access")
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), #""state-8""#)
        XCTAssertNotNil(request.value(forHTTPHeaderField: "Idempotency-Key").flatMap(UUID.init(uuidString:)))
        let items = try XCTUnwrap(ShoppingFixture.json(request)["items"] as? [[String: Any]])
        XCTAssertEqual(items.map { $0["ingredient_id"] as? String }, ["cheese", "milk"])
        XCTAssertEqual(items.map { ($0["quantity"] as? [String: Any])?["value"] as? Double }, [400, 1_000])
        XCTAssertEqual(items.map { ($0["quantity"] as? [String: Any])?["unit"] as? String }, ["g", "ml"])
        XCTAssertEqual(session.revision?.stateVersion, 9)
        XCTAssertEqual(model.transferState, .completed)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(model.markedCount, 0)
    }

    func testPlanUpdatesExistingPackageCountWithoutSummingOrChangingMarkedRows() async throws {
        let requests = ShoppingRequestLog()
        let (model, _) = try await makeModel { request in
            switch request.url?.path {
            case ShoppingFixture.state:
                return try SessionFixture.stateResponse(request)
            case ShoppingFixture.single:
                return try ShoppingFixture.recommendation(request, cheesePackages: 1)
            case ShoppingFixture.budget:
                return try ShoppingFixture.recommendation(request, version: 8)
            default:
                _ = await requests.record(request)
                return try ShoppingFixture.mutation(request, version: 9)
            }
        }

        model.budgetInput = "600"
        await model.loadRecommendation(.singlePurchase)
        let single = try XCTUnwrap(result(model).suggestions.first)
        XCTAssertTrue(model.add(single))
        let cheese = try XCTUnwrap(model.items.first)
        _ = model.setPurchased(true, id: cheese.id)

        model.servings = 4
        await model.loadRecommendation(.budget)
        let plan = try XCTUnwrap(result(model).suggestions.first)
        XCTAssertEqual(model.addition(for: plan), .marked)
        XCTAssertFalse(model.add(plan))
        XCTAssertEqual(model.items.count, 1)
        XCTAssertEqual(model.items.first?.estimatedPrice, 230)
        XCTAssertEqual(model.markedCount, 1)

        _ = model.setPurchased(false, id: cheese.id)
        XCTAssertEqual(model.addition(for: plan), .update)
        XCTAssertTrue(model.add(plan))
        XCTAssertEqual(model.addition(for: plan), .alreadyAdded)
        XCTAssertFalse(model.add(plan))
        XCTAssertEqual(model.items.count, 2)
        XCTAssertEqual(model.items.first?.estimatedPrice, 460)

        _ = model.setPurchased(true, id: cheese.id)
        await model.confirmTransfer()
        let sent = await requests.all
        let request = try XCTUnwrap(sent.first)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), #""state-8""#)
        let items = try XCTUnwrap(ShoppingFixture.json(request)["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 1)
        let quantity = try XCTUnwrap(items.first?["quantity"] as? [String: Any])
        XCTAssertEqual(quantity["value"] as? Double, 400)
    }

    func test412ReloadsRevisionAndPreservesMarksUntilExplicitConfirmation() async throws {
        let requests = ShoppingRequestLog()
        let (model, session) = try await makeModel { request in
            if request.url?.path == ShoppingFixture.budget {
                return try ShoppingFixture.recommendation(request)
            }
            switch await requests.record(request) {
            case 1:
                return try SessionFixture.stateResponse(request)
            case 2:
                return try SessionFixture.error(request, status: 412, code: "state_conflict")
            case 3:
                return try SessionFixture.stateResponse(request, version: 8)
            default:
                return try ShoppingFixture.mutation(request, version: 9)
            }
        }
        try await addBudget(model)
        let cheese = try XCTUnwrap(model.items.first)
        _ = model.setPurchased(true, id: cheese.id)

        await model.confirmTransfer()
        XCTAssertEqual(model.transferState, .needsConfirmation)
        XCTAssertEqual(model.items.filter(\.isPurchased).map(\.id), [cheese.id])
        XCTAssertEqual(session.revision?.stateVersion, 8)
        let afterConflict = await requests.all
        XCTAssertEqual(
            afterConflict.compactMap { $0.url?.path },
            [ShoppingFixture.state, ShoppingFixture.purchased, ShoppingFixture.state]
        )
        let attempted = try XCTUnwrap(afterConflict.dropFirst().first)
        XCTAssertEqual(attempted.value(forHTTPHeaderField: "If-Match"), #""state-7""#)

        await model.confirmTransfer()
        let afterConfirmation = await requests.all
        let latest = try XCTUnwrap(afterConfirmation.last)
        XCTAssertEqual(latest.url?.path, ShoppingFixture.purchased)
        XCTAssertEqual(latest.value(forHTTPHeaderField: "If-Match"), #""state-8""#)
        XCTAssertEqual(
            try ShoppingFixture.json(latest) as NSDictionary, try ShoppingFixture.json(attempted) as NSDictionary)
        XCTAssertEqual(model.transferState, .completed)
        XCTAssertEqual(model.items.map(\.name), ["Молоко"])
        XCTAssertEqual(session.revision?.stateVersion, 9)
    }

    func testTimedOutTransferReplaysSameOperationWithoutAddingTwice() async throws {
        let pantry = ShoppingReplayPantry()
        let (model, session) = try await makeModel { request in
            switch request.url?.path {
            case ShoppingFixture.state:
                return try SessionFixture.stateResponse(request)
            case ShoppingFixture.budget:
                return try ShoppingFixture.recommendation(request)
            default:
                return try await pantry.respond(request)
            }
        }
        try await addBudget(model)
        let item = try XCTUnwrap(model.items.first)
        _ = model.setPurchased(true, id: item.id)
        await model.confirmTransfer()
        XCTAssertEqual(model.transferState, .retry)
        XCTAssertEqual(model.markedCount, 1)
        XCTAssertNil(model.setPurchased(false, id: item.id))
        XCTAssertEqual(session.revision?.stateVersion, 7)

        await model.confirmTransfer()
        let added = await pantry.added
        let calls = await pantry.calls
        XCTAssertEqual(added, 1)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(session.revision?.stateVersion, 8)
        XCTAssertEqual(model.transferState, .completed)
        XCTAssertEqual(model.items.map(\.name), ["Молоко"])
    }

    private func makeModel(
        respond: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) async throws -> (ServerShoppingModel, SessionStore) {
        let session = try SessionFixture.store(
            storage: SessionTestStorage(.active(SessionFixture.original)), respond: respond
        )
        await session.restore()
        let account = try XCTUnwrap(session.account)
        return (ServerShoppingModel(repository: ShoppingRepository(session: session, account: account)), session)
    }

    private func result(_ model: ServerShoppingModel) throws -> ShoppingRecommendation {
        guard case .result(let result) = model.recommendation else {
            XCTFail("Expected a recommendation result")
            throw APIClientError.invalidResponse(nil)
        }
        return result
    }

    private func addBudget(_ model: ServerShoppingModel) async throws {
        model.budgetInput = "600"
        await model.loadRecommendation(.budget)
        let suggestion = try XCTUnwrap(result(model).suggestions.first)
        model.add(suggestion)
        model.add(suggestion)
        XCTAssertEqual(model.items.count, 2)
    }
}

private actor ShoppingRequestLog {
    private(set) var all: [URLRequest] = []

    func record(_ request: URLRequest) -> Int {
        all.append(request)
        return all.count
    }
}

private actor ShoppingReplayPantry {
    private(set) var added = 0
    private(set) var calls = 0
    private var original: URLRequest?

    func respond(_ request: URLRequest) throws -> (Data, URLResponse) {
        XCTAssertEqual(request.url?.path, ShoppingFixture.purchased)
        calls += 1
        if let original {
            let key = try XCTUnwrap(original.value(forHTTPHeaderField: "Idempotency-Key"))
            let precondition = original.value(forHTTPHeaderField: "If-Match")
            let body = try ShoppingFixture.json(original) as NSDictionary
            guard request.value(forHTTPHeaderField: "Idempotency-Key") == key,
                request.value(forHTTPHeaderField: "If-Match") == precondition,
                try ShoppingFixture.json(request) as NSDictionary == body
            else {
                return try SessionFixture.error(request, status: 409, code: "idempotency_conflict")
            }
            return try ShoppingFixture.mutation(request, version: 8)
        }

        added += 1
        original = request
        throw URLError(.timedOut)
    }
}

private enum ShoppingFixture {
    static let state = "/api/v1/me/state"
    static let purchased = "/api/v1/me/pantry/purchased"
    static let budget = "/api/v1/recommendations/budget"
    static let single = "/api/v1/recommendations/single-purchase"

    static func json(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    static func recommendation(
        _ request: URLRequest, status: String = "found", version: Int = 7, cheesePackages: Int = 2
    ) throws -> (Data, URLResponse) {
        let payload = try json(request)
        let found = status == "found"
        var body: [String: Any] = [
            "request_id": try XCTUnwrap(payload["request_id"]),
            "servings": try XCTUnwrap(payload["servings"]),
            "state_version": version,
            "catalog_version": "fixture-catalog",
            "status": status,
            "semantics": "alternatives",
            "unpriced_recipe_ids": status == "insufficient_data" ? ["unknown"] : []
        ]
        let cheesePrice = cheesePackages * 23_000
        let cheese: [String: Any] = [
            "key": "cheese:package-200g", "ingredient_id": "cheese", "package_id": "package-200g", "name": "Сыр",
            "package_quantity": ["value": 200, "unit": "g"], "package_count": cheesePackages,
            "total_price": ["minor_units": cheesePrice, "currency": "RUB"]
        ]
        let milk: [String: Any] = [
            "key": "milk:package-1l", "ingredient_id": "milk", "package_id": "package-1l", "name": "Молоко",
            "package_quantity": ["value": 1_000, "unit": "ml"], "package_count": 1,
            "total_price": ["minor_units": 9_500, "currency": "RUB"]
        ]
        if request.url?.path == single {
            body["options"] =
                found
                ? [
                    ["shopping_item": cheese, "unlocked_recipe_ids": ["omelet", "pasta"]],
                    ["shopping_item": milk, "unlocked_recipe_ids": ["porridge"]]
                ] : []
        } else {
            body["shopping_items"] = found ? [cheese, milk] : []
            body["unlocked_recipe_ids"] = found ? ["omelet", "pasta", "porridge"] : []
            let total: [String: Any] = ["minor_units": cheesePrice + 9_500, "currency": "RUB"]
            body["total_cost"] = found ? total : NSNull()
        }
        return try SessionFixture.response(request, body: body, etag: #""state-\#(version)""#)
    }

    static func mutation(_ request: URLRequest, version: Int) throws -> (Data, URLResponse) {
        try SessionFixture.response(
            request, body: ["state_version": version, "items": []], etag: #""state-\#(version)""#
        )
    }
}
