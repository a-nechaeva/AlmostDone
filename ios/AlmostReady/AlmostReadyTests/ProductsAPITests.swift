import Foundation
import XCTest

@testable import AlmostReady

final class ProductsAPITests: XCTestCase {
    @MainActor
    func testSearchAndPantryWritesUseContractAndPublishRevisions() async throws {
        let log = ProductRequestLog()
        let repository = try await repository { request in
            let index = await log.append(request)
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/v1/me/state"):
                return try SessionFixture.stateResponse(request)
            case ("GET", "/api/v1/me/pantry"):
                return try Self.pantry(request, version: 7, includesSalt: true)
            case ("GET", "/api/v1/ingredients"):
                return try Self.ingredients(request, id: "cheese/aged")
            case ("POST", "/api/v1/me/pantry/add"):
                return try Self.pantry(request, version: 8, quantity: NSNull(), includesSalt: true)
            case ("PUT", _):
                return try index == 6
                    ? Self.pantry(request, version: 9, quantity: NSNull(), includesSalt: true)
                    : Self.pantry(request, version: 10, includesSalt: true)
            case ("DELETE", _):
                return try Self.pantry(request, version: 11)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        let model = PantryModel(repository: repository)
        await model.reload()
        let initial = try XCTUnwrap(model.snapshot)
        XCTAssertEqual(initial.revision.stateVersion, 7)
        XCTAssertEqual(initial.items.map(\.id), ["salt"])

        let ingredients = try await repository.search("сыр+")
        let ingredient = try XCTUnwrap(ingredients.items.first)
        XCTAssertEqual(ingredient.allowedUnits, [.grams, .pieces])
        let add = PantryDraft(kind: .add(ingredient), snapshot: initial)
        add.quantityText = "0"
        XCTAssertFalse(add.canSave)
        let zeroAdded = await model.save(add)
        XCTAssertFalse(zeroAdded)
        add.quantityText = "3"
        add.unit = .milliliters
        XCTAssertFalse(add.canSave)
        add.quantityText = ""
        let added = await model.save(add)
        XCTAssertTrue(added)
        let afterAdd = try XCTUnwrap(model.snapshot)
        let row = try XCTUnwrap(afterAdd.items.first)
        XCTAssertNil(row.quantity)
        XCTAssertEqual(repository.session.revision?.stateVersion, 8)

        let edit = PantryDraft(kind: .edit(row), snapshot: afterAdd)
        await edit.loadUnits(from: repository)
        XCTAssertEqual(edit.allowedUnits, [.grams, .pieces])
        let setUnknown = await model.save(edit)
        XCTAssertTrue(setUnknown)
        XCTAssertEqual(repository.session.revision?.stateVersion, 9)

        let beforeZero = try XCTUnwrap(model.snapshot)
        let zero = PantryDraft(kind: .edit(row), snapshot: beforeZero)
        await zero.loadUnits(from: repository)
        zero.quantityText = "0"
        let setZero = await model.save(zero)
        XCTAssertTrue(setZero)
        let beforeDelete = try XCTUnwrap(model.snapshot)
        XCTAssertEqual(beforeDelete.items.map(\.id), ["salt"])
        XCTAssertEqual(repository.session.revision?.stateVersion, 10)

        let salt = try XCTUnwrap(beforeDelete.items.first)
        let delete = PantryDraft(kind: .edit(salt), snapshot: beforeDelete)
        let deleted = await model.save(delete, deleting: true)
        XCTAssertTrue(deleted)
        XCTAssertTrue(model.snapshot?.items.isEmpty == true)
        XCTAssertEqual(repository.session.revision?.stateVersion, 11)

        let requests = await log.requests
        guard requests.count == 9 else { return XCTFail("Expected nine requests, got \(requests.count)") }
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "GET", "GET", "POST", "GET", "PUT", "GET", "PUT", "DELETE"])
        XCTAssertTrue(
            requests.allSatisfy {
                $0.value(forHTTPHeaderField: "Authorization") == "Bearer \(SessionFixture.original.accessToken)"
            })
        XCTAssertEqual(
            requests[2].url?.absoluteString, "https://example.test/api/v1/ingredients?q=%D1%81%D1%8B%D1%80%2B")

        let posted = try Self.jsonBody(requests[3])
        XCTAssertEqual(posted["ingredient_id"] as? String, "cheese/aged")
        XCTAssertTrue(posted["quantity"] is NSNull)
        XCTAssertEqual(requests[3].value(forHTTPHeaderField: "If-Match"), #""state-7""#)
        let key = try XCTUnwrap(requests[3].value(forHTTPHeaderField: "Idempotency-Key"))
        XCTAssertNotNil(UUID(uuidString: key))

        let set = try Self.jsonBody(requests[5])
        XCTAssertEqual(Set(set.keys), ["quantity"])
        XCTAssertTrue(set["quantity"] is NSNull)
        XCTAssertEqual(requests[5].value(forHTTPHeaderField: "If-Match"), #""state-8""#)
        let setZeroBody = try XCTUnwrap(try Self.jsonBody(requests[7])["quantity"] as? [String: Any])
        XCTAssertEqual(setZeroBody["value"] as? Double, 0)
        XCTAssertEqual(setZeroBody["unit"] as? String, "g")
        XCTAssertEqual(requests[7].value(forHTTPHeaderField: "If-Match"), #""state-9""#)
        XCTAssertNil(requests[8].httpBody)
        XCTAssertEqual(requests[8].value(forHTTPHeaderField: "If-Match"), #""state-10""#)
        XCTAssertEqual(requests[8].url?.path, "/api/v1/me/pantry/salt")
        XCTAssertNil(requests[8].value(forHTTPHeaderField: "Idempotency-Key"))
        for index in [5, 7] {
            XCTAssertEqual(requests[index].url?.absoluteString, "https://example.test/api/v1/me/pantry/cheese%2Faged")
            XCTAssertNil(requests[index].value(forHTTPHeaderField: "Idempotency-Key"))
        }
    }

    @MainActor
    func testStaleSearchCannotReplaceCurrentResultsAndFailureCanRetry() async throws {
        let firstStarted = SessionResponseGate()
        let allowFirstResponse = SessionResponseGate()
        let log = ProductRequestLog()
        let repository = try await repository { request in
            if request.url?.path == "/api/v1/me/state" {
                return try SessionFixture.stateResponse(request)
            }
            XCTAssertEqual(request.url?.path, "/api/v1/ingredients")
            XCTAssertEqual(request.httpMethod, "GET")
            let index = await log.append(request)
            let url = try XCTUnwrap(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
            switch query {
            case "сыр":
                await firstStarted.open()
                await allowFirstResponse.wait()
                return try Self.ingredients(request, id: "cheese/aged")
            case "рис":
                return try Self.ingredients(request, id: "rice")
            default:
                if index == 3 { throw URLError(.notConnectedToInternet) }
                return try Self.ingredients(request, id: nil)
            }
        }
        let search = IngredientSearchModel(repository: repository)
        search.query = "сыр"
        let firstID = search.requestID
        let first = Task { await search.search(request: firstID) }
        await firstStarted.wait()

        search.query = "  рис  "
        if case .loading = search.phase {} else { XCTFail("Expected search loading") }
        await search.search(request: search.requestID)
        await allowFirstResponse.open()
        await first.value
        guard case .results(let current) = search.phase else { return XCTFail("Expected search results") }
        XCTAssertEqual(current.map(\.id), ["rice"])

        search.query = "нет"
        await search.search(request: search.requestID)
        if case .failed = search.phase {} else { XCTFail("Expected search failure") }
        search.restart()
        await search.search(request: search.requestID)
        guard case .results(let empty) = search.phase else { return XCTFail("Expected empty result") }
        XCTAssertTrue(empty.isEmpty)
    }

    @MainActor
    func testCatalogLoadsNextPageAndRespectsRetryAfter() async throws {
        let log = ProductRequestLog()
        let repository = try await repository { request in
            if request.url?.path == "/api/v1/me/state" { return try SessionFixture.stateResponse(request) }
            let index = await log.append(request)
            switch index {
            case 1: return try Self.ingredients(request, id: "cheese/aged", cursor: "next+page")
            case 2: return try SessionFixture.error(request, status: 429, code: "rate_limited", retryAfter: "1")
            case 3: return try Self.ingredients(request, id: "cheese/fresh")
            default: throw URLError(.unsupportedURL)
            }
        }
        let search = IngredientSearchModel(repository: repository)
        search.query = "сыр"
        await search.search(request: search.requestID)
        XCTAssertEqual(search.nextCursor, "next+page")
        await search.loadMore()
        XCTAssertTrue(search.pageLoadFailed)
        guard case .results(let firstPage) = search.phase else { return XCTFail("Expected first page to remain") }
        XCTAssertEqual(firstPage.map(\.id), ["cheese/aged"])
        await search.loadMore()

        guard case .results(let combined) = search.phase else { return XCTFail("Expected combined pages") }
        XCTAssertEqual(combined.map(\.id), ["cheese/aged", "cheese/fresh"])
        XCTAssertFalse(search.pageLoadFailed)
        XCTAssertNil(search.nextCursor)
        let requests = await log.requests
        guard requests.count == 3 else { return XCTFail("Expected three catalog requests") }
        let times = await log.times
        XCTAssertGreaterThanOrEqual(times[1].duration(to: times[2]), .seconds(1))
        XCTAssertEqual(requests[1].url?.absoluteString, requests[2].url?.absoluteString)
        let url = try XCTUnwrap(requests[2].url)
        XCTAssertEqual(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            [URLQueryItem(name: "q", value: "сыр"), URLQueryItem(name: "cursor", value: "next+page")]
        )
    }

    @MainActor
    func testReloadCanReplaceAnInFlightCancelledPantryRequest() async throws {
        let firstStarted = SessionResponseGate()
        let allowFirstResponse = SessionResponseGate()
        let log = ProductRequestLog()
        let repository = try await repository { request in
            if request.url?.path == "/api/v1/me/state" { return try SessionFixture.stateResponse(request) }
            if await log.append(request) == 1 {
                await firstStarted.open()
                await allowFirstResponse.wait()
                return try Self.pantry(request, version: 7)
            }
            return try Self.pantry(request, version: 8, quantity: NSNull())
        }
        let model = PantryModel(repository: repository)
        let first = Task { await model.reloadIfNeeded() }
        await firstStarted.wait()
        first.cancel()
        await model.reloadIfNeeded()
        await allowFirstResponse.open()
        await first.value

        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.loadFailed)
        XCTAssertEqual(model.snapshot?.revision.stateVersion, 8)
        XCTAssertEqual(model.snapshot?.items.map(\.id), ["cheese/aged"])
    }

    @MainActor
    func testConflictReloadsRevisionAndPantryAndPreservesDraftForExplicitResubmission() async throws {
        let log = ProductRequestLog()
        let repository = try await repository { request in
            let index = await log.append(request)
            switch index {
            case 1: return try SessionFixture.stateResponse(request)
            case 2: return try Self.pantry(request, version: 7, quantity: ["value": 50, "unit": "g"])
            case 3: return try Self.ingredients(request, id: "cheese/aged")
            case 4: return try SessionFixture.error(request, status: 412, code: "state_conflict")
            case 5: return try SessionFixture.stateResponse(request, version: 8)
            case 6: return try Self.pantry(request, version: 8, quantity: ["value": 100, "unit": "g"])
            case 7: return try Self.pantry(request, version: 9, quantity: ["value": 12.5, "unit": "pcs"])
            default: throw URLError(.unsupportedURL)
            }
        }

        let model = PantryModel(repository: repository)
        await model.reload()
        let initial = try XCTUnwrap(model.snapshot)
        let item = try XCTUnwrap(initial.items.first)
        let draft = PantryDraft(kind: .edit(item), snapshot: initial)
        await draft.loadUnits(from: repository)
        draft.quantityText = "12,5"
        draft.unit = .pieces

        let savedBeforeRebase = await model.save(draft)
        XCTAssertFalse(savedBeforeRebase)
        XCTAssertEqual(draft.issue, .conflict)
        XCTAssertEqual(draft.quantityText, "12,5")
        XCTAssertEqual(draft.unit, .pieces)
        XCTAssertEqual(draft.currentItem?.quantity?.value, 100)
        XCTAssertEqual(model.snapshot?.items.first?.quantity?.value, 100)
        XCTAssertEqual(draft.revision.stateVersion, 8)
        XCTAssertEqual(repository.session.revision?.stateVersion, 8)
        let beforeRetry = await log.requests
        guard beforeRetry.count == 6 else { return XCTFail("Expected six requests, got \(beforeRetry.count)") }
        XCTAssertEqual(beforeRetry.suffix(3).map(\.httpMethod), ["PUT", "GET", "GET"])
        XCTAssertEqual(beforeRetry[4].url?.path, "/api/v1/me/state")
        XCTAssertEqual(beforeRetry[5].url?.path, "/api/v1/me/pantry")
        XCTAssertEqual(beforeRetry[3].value(forHTTPHeaderField: "If-Match"), #""state-7""#)

        let savedAfterRebase = await model.save(draft)
        XCTAssertTrue(savedAfterRebase)
        XCTAssertEqual(model.snapshot?.items.first?.quantity, PantryQuantity(value: 12.5, unit: .pieces))
        XCTAssertEqual(repository.session.revision?.stateVersion, 9)
        let retried = await log.requests.last
        let request = try XCTUnwrap(retried)
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), #""state-8""#)
        let body = try XCTUnwrap(try Self.jsonBody(request)["quantity"] as? [String: Any])
        XCTAssertEqual(body["value"] as? Double, 12.5)
        XCTAssertEqual(body["unit"] as? String, "pcs")
    }

    @MainActor
    func testTimedOutAddReplaysOriginalOperationWithoutAddingTwice() async throws {
        let backend = AddReplayFixture()
        let repository = try await repository { request in
            try await backend.respond(request)
        }
        let model = PantryModel(repository: repository)
        await model.reload()
        let initial = try XCTUnwrap(model.snapshot)
        let results = try await repository.search("сыр")
        let ingredient = try XCTUnwrap(results.items.first)
        let draft = PantryDraft(kind: .add(ingredient), snapshot: initial)
        draft.quantityText = "200"

        let first = await model.save(draft)
        XCTAssertFalse(first)
        XCTAssertTrue(draft.hasPendingAdd)
        XCTAssertEqual(draft.issue, .uncertainAdd)
        XCTAssertEqual(model.snapshot?.items.first?.quantity?.value, 500)
        draft.quantityText = "300"

        let retried = await model.save(draft)
        XCTAssertTrue(retried)
        XCTAssertFalse(draft.hasPendingAdd)
        XCTAssertEqual(model.snapshot?.items.first?.quantity?.value, 750)
        XCTAssertEqual(repository.session.revision?.stateVersion, 8)
        let requests = await backend.addRequests
        XCTAssertEqual(requests.count, 2)
        let firstRequest = try XCTUnwrap(requests.first)
        let replayRequest = try XCTUnwrap(requests.last)
        let key = try XCTUnwrap(firstRequest.value(forHTTPHeaderField: "Idempotency-Key"))
        XCTAssertNotNil(UUID(uuidString: key))
        XCTAssertEqual(replayRequest.value(forHTTPHeaderField: "Idempotency-Key"), key)
        XCTAssertEqual(replayRequest.value(forHTTPHeaderField: "If-Match"), #""state-7""#)
        let firstBody = try Self.jsonBody(firstRequest)
        let replayBody = try Self.jsonBody(replayRequest)
        XCTAssertEqual(firstBody as NSDictionary, replayBody as NSDictionary)
        let applied = await backend.applied
        XCTAssertEqual(applied, 1)
    }

    @MainActor
    private func repository(
        respond: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) async throws -> ProductsRepository {
        let session = try SessionFixture.store(
            storage: SessionTestStorage(.active(SessionFixture.original)), respond: respond)
        await session.restore()
        return ProductsRepository(session: session, account: try XCTUnwrap(session.account))
    }

    fileprivate static func pantry(
        _ request: URLRequest, version: Int, quantity: Any? = nil, includesSalt: Bool = false
    ) throws -> (Data, URLResponse) {
        var items = quantity.map { [["ingredient_id": "cheese/aged", "name": "Сыр", "quantity": $0]] } ?? []
        if includesSalt { items.append(["ingredient_id": "salt", "name": "Соль", "quantity": NSNull()]) }
        return try SessionFixture.response(
            request, body: ["state_version": version, "items": items], etag: #""state-\#(version)""#
        )
    }

    fileprivate static func ingredients(
        _ request: URLRequest, id: String?, cursor: String? = nil
    ) throws -> (Data, URLResponse) {
        let items = id.map { [["id": $0, "name": "Сыр", "allowed_units": ["g", "pcs"]]] } ?? []
        return try SessionFixture.response(
            request,
            body: [
                "items": items, "catalog_version": "catalog-1", "state_version": 7,
                "page": ["next_cursor": cursor as Any? ?? NSNull(), "has_more": cursor != nil]
            ]
        )
    }

    private static func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private actor ProductRequestLog {
    private(set) var requests: [URLRequest] = []
    private(set) var times: [ContinuousClock.Instant] = []

    func append(_ request: URLRequest) -> Int {
        requests.append(request)
        times.append(.now)
        return requests.count
    }
}

private actor AddReplayFixture {
    private(set) var addRequests: [URLRequest] = []
    private(set) var applied = 0
    private var appliedKeys: Set<String> = []

    func respond(_ request: URLRequest) throws -> (Data, URLResponse) {
        switch request.url?.path {
        case "/api/v1/me/state":
            return try SessionFixture.stateResponse(request)
        case "/api/v1/me/pantry":
            // A second device changes the pantry after the timed-out write.
            let value = applied == 0 ? 500 : 500 + 200 * applied + 50
            return try ProductsAPITests.pantry(
                request, version: applied == 0 ? 7 : 9, quantity: ["value": value, "unit": "g"]
            )
        case "/api/v1/ingredients":
            return try ProductsAPITests.ingredients(request, id: "cheese/aged")
        case "/api/v1/me/pantry/add":
            addRequests.append(request)
            let key = try XCTUnwrap(request.value(forHTTPHeaderField: "Idempotency-Key"))
            if appliedKeys.insert(key).inserted {
                applied += 1
                throw URLError(.timedOut)
            }
            return try ProductsAPITests.pantry(
                request, version: 8, quantity: ["value": 500 + 200 * applied, "unit": "g"])
        default:
            throw URLError(.unsupportedURL)
        }
    }
}
