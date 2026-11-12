import Foundation
import XCTest

@testable import AlmostReady

final class PhotoImportTests: XCTestCase {
    @MainActor
    func testMultipartPollsByServerDelayAndStopsOnEmptyResult() async throws {
        let trace = RecognitionTestTrace()
        let photo = try Self.photo()
        let model = try await makeModel {
            await trace.recordDelay($0)
        } respond: { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/v1/recognitions"):
                try Self.assertMultipart(request, photo: photo, kind: "receipt")
                return try Self.recognition(request, status: "queued", poll: 1, retryAfter: "3")
            case ("GET", "/api/v1/recognitions/job"):
                let index = await trace.recordRequest(request)
                XCTAssertNil(request.httpBody)
                return try Self.recognition(request, status: index == 1 ? "processing" : "succeeded", poll: 2)
            default:
                return try Self.initialState(request)
            }
        }

        await model.recognize(photo)

        XCTAssertEqual(model.phase, .empty)
        XCTAssertTrue(model.lines.isEmpty)
        XCTAssertFalse(model.canRetryRecognition)
        let delays = await trace.delays
        XCTAssertEqual(delays, [.seconds(3), .seconds(2)])
    }

    @MainActor
    func testCancellationDuringPollWaitStopsGetAndDiscardsPhoto() async throws {
        let waiting = SessionResponseGate()
        let resume = SessionResponseGate()
        let polls = RecognitionTestTrace()
        let model = try await makeModel { _ in
            await waiting.open()
            await resume.wait()
        } respond: { request in
            switch request.url?.path {
            case "/api/v1/recognitions":
                return try Self.recognition(request, status: "queued")
            case "/api/v1/recognitions/job":
                _ = await polls.recordRequest(request)
                return try Self.recognition(request, status: "succeeded")
            default:
                return try Self.initialState(request)
            }
        }
        let photo = try Self.photo()

        let task = Task { await model.recognize(photo) }
        await waiting.wait()
        task.cancel()
        model.chooseAnotherPhoto()
        await resume.open()
        await task.value

        XCTAssertEqual(model.phase, .source)
        XCTAssertFalse(model.canRetryRecognition)
        let pollRequests = await polls.requests
        XCTAssertTrue(pollRequests.isEmpty)
    }

    @MainActor
    func testUploadRetryUsesSameKeyAndPollRetryDoesNotUploadAgain() async throws {
        let uploads = RecognitionTestTrace()
        let polls = RecognitionTestTrace()
        let model = try await makeModel {
            await polls.recordDelay($0)
        } respond: { request in
            switch request.url?.path {
            case "/api/v1/recognitions":
                let index = await uploads.recordRequest(request)
                if index == 1 { throw URLError(.timedOut) }
                return try Self.recognition(request, status: "processing")
            case "/api/v1/recognitions/job":
                let index = await polls.recordRequest(request)
                if index == 1 {
                    return try SessionFixture.error(
                        request, status: 503, code: "service_unavailable", retryAfter: "120")
                }
                return try Self.recognition(request, status: "succeeded")
            default:
                return try Self.initialState(request)
            }
        }

        await model.recognize(try Self.photo())
        XCTAssertEqual(model.phase, .failed)
        XCTAssertTrue(model.canRetryRecognition)
        await model.retryRecognition()
        XCTAssertEqual(model.phase, .failed)
        XCTAssertTrue(model.canRetryRecognition)
        await model.retryRecognition()
        XCTAssertEqual(model.phase, .empty)

        let requests = await uploads.requests
        XCTAssertEqual(requests.count, 2)
        let keys = requests.compactMap { $0.value(forHTTPHeaderField: "Idempotency-Key") }
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys.first, keys.last)
        let delays = await polls.delays
        XCTAssertEqual(delays.count, 2)
        XCTAssertEqual(delays.first, .seconds(1))
        XCTAssertGreaterThan(delays.last ?? .zero, .seconds(60))
    }

    @MainActor
    func testFailedJobRetryStartsNewJob() async throws {
        let uploads = RecognitionTestTrace()
        let model = try await makeModel { request in
            if request.url?.path == "/api/v1/recognitions" {
                let index = await uploads.recordRequest(request)
                return try Self.recognition(
                    request, status: index == 1 ? "failed" : "succeeded", retryableFailure: index == 1)
            }
            return try Self.initialState(request)
        }
        await model.recognize(try Self.photo())
        XCTAssertEqual(model.phase, .failed)
        XCTAssertTrue(model.canRetryRecognition)
        await model.retryRecognition()
        XCTAssertEqual(model.phase, .empty)
        let requests = await uploads.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertNotEqual(
            requests.first?.value(forHTTPHeaderField: "Idempotency-Key"),
            requests.last?.value(forHTTPHeaderField: "Idempotency-Key")
        )
    }

    @MainActor
    func testImportReplaysNullAndSameSelectionWithoutDuplicatingPantry() async throws {
        let ledger = RecognitionImportLedger()
        let model = try await makeModel { request in
            switch request.url?.path {
            case "/api/v1/recognitions":
                return try Self.recognition(request, status: "succeeded", kind: "products", lines: Self.lines())
            case "/api/v1/ingredients":
                return try SessionFixture.response(
                    request,
                    body: ["items": [["id": "cheese", "name": "Сыр", "allowed_units": ["g"]]], "page": [:]]
                )
            case "/api/v1/recognition-imports":
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), #""state-7""#)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer old-access")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
                if try await ledger.accept(request) { throw URLError(.timedOut) }
                return try Self.imported(request, version: 8)
            case "/api/v1/me/pantry":
                let items = await ledger.items
                if !items.isEmpty {
                    return try SessionFixture.error(request, status: 503, code: "service_unavailable")
                }
                return try Self.pantry(request, version: 7)
            default:
                return try Self.initialState(request)
            }
        }

        model.kind = .products
        await model.recognize(try Self.photo())
        let found = try await model.pantry.repository.search("сыр")
        model.select(try XCTUnwrap(found.items.first), for: "line-1")
        model.setSelected(false, for: "line-2")
        await model.confirm()

        XCTAssertEqual(model.phase, .review)
        XCTAssertEqual(model.problem, .uncertain)
        XCTAssertTrue(model.hasPendingImport)
        XCTAssertFalse(model.canEdit)
        XCTAssertEqual(model.pantry.repository.session.revision?.stateVersion, 7)
        XCTAssertEqual(model.pantry.snapshot?.items.count, 0)

        model.setSelected(true, for: "line-2")
        await model.confirm()

        XCTAssertEqual(model.phase, .imported)
        XCTAssertFalse(model.hasPendingImport)
        XCTAssertEqual(model.pantry.repository.session.revision?.stateVersion, 8)
        XCTAssertEqual(model.pantry.snapshot?.items.map(\.ingredientID), ["cheese"])
        XCTAssertTrue(model.pantry.loadFailed)
        XCTAssertNil(model.pantry.snapshot?.items.first?.quantity)
        let items = await ledger.items
        XCTAssertEqual(items, ["cheese"])
        let requests = await ledger.requests
        XCTAssertEqual(requests.count, 2)
        let first = try XCTUnwrap(requests.first)
        let last = try XCTUnwrap(requests.last)
        XCTAssertEqual(
            first.value(forHTTPHeaderField: "Idempotency-Key"), last.value(forHTTPHeaderField: "Idempotency-Key"))
        let body = try Self.jsonBody(first)
        XCTAssertEqual(body, try Self.jsonBody(last))
        XCTAssertEqual(
            body,
            [
                "recognition_id": "job", "kind": "products",
                "items": [["line_id": "line-1", "ingredient_id": "cheese", "quantity": NSNull()]]
            ]
        )
    }

    @MainActor
    func testConflictPreservesSelectionAndRequiresNewConfirmation() async throws {
        let imports = RecognitionTestTrace()
        let model = try await makeModel { request in
            switch request.url?.path {
            case "/api/v1/recognitions":
                return try Self.recognition(request, status: "succeeded", lines: Self.lines())
            case "/api/v1/recognition-imports":
                let index = await imports.recordRequest(request)
                if index == 1 { return try SessionFixture.error(request, status: 412, code: "state_conflict") }
                return try Self.imported(request, version: 9)
            case "/api/v1/me/state":
                let count = await imports.requests.count
                return try SessionFixture.stateResponse(request, version: count == 0 ? 7 : 8)
            case "/api/v1/me/pantry":
                let count = await imports.requests.count
                return try Self.pantry(request, version: 7 + count)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        await model.recognize(try Self.photo())
        await model.confirm()

        XCTAssertEqual(model.phase, .review)
        XCTAssertEqual(model.problem, .conflict)
        XCTAssertEqual(model.lines.filter(\.isSelected).map(\.id), ["line-2"])
        XCTAssertTrue(model.canConfirm)
        let count = await imports.requests.count
        XCTAssertEqual(count, 1)

        await model.confirm()
        XCTAssertEqual(model.phase, .imported)
        let requests = await imports.requests
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "If-Match") }, [#""state-7""#, #""state-8""#])
        XCTAssertNotEqual(
            requests.first?.value(forHTTPHeaderField: "Idempotency-Key"),
            requests.last?.value(forHTTPHeaderField: "Idempotency-Key")
        )
    }

    @MainActor
    func testImportResponseFromSignedOutAccountIsDiscarded() async throws {
        let started = SessionResponseGate()
        let reply = SessionResponseGate()
        let model = try await makeModel { request in
            switch request.url?.path {
            case "/api/v1/recognitions":
                return try Self.recognition(request, status: "succeeded", lines: Self.lines())
            case "/api/v1/recognition-imports":
                await started.open()
                await reply.wait()
                return try Self.imported(request, version: 8)
            case "/api/v1/auth/logout":
                return try SessionFixture.response(request, status: 204)
            default:
                return try Self.initialState(request)
            }
        }

        await model.recognize(try Self.photo())
        let confirmation = Task { await model.confirm() }
        await started.wait()
        let session = model.pantry.repository.session
        _ = try await session.signOut()
        await reply.open()
        await confirmation.value

        XCTAssertNil(session.revision)
        XCTAssertFalse(model.hasPendingImport)
        XCTAssertTrue(model.lines.isEmpty)
        XCTAssertEqual(model.pantry.snapshot?.revision.stateVersion, 7)
    }

    @MainActor
    func testCorrectedIngredientDoesNotReuseQuantityConvertedForAnotherProduct() throws {
        let json = try JSONSerialization.data(withJSONObject: [
            "line_id": "line-1", "raw_name": "Продукт", "status": "matched",
            "candidates": [
                ["ingredient_id": "yogurt", "name": "Йогурт", "confidence": 0.2],
                ["ingredient_id": "milk", "name": "Молоко", "confidence": 0.9]
            ],
            "suggested_quantity": ["value": 400, "unit": "ml"]
        ])
        var line = PhotoImportLine(try JSONDecoder().decode(RecognitionLine.self, from: json))
        XCTAssertEqual(line.item?.ingredientID, "milk")
        XCTAssertEqual(line.item?.quantity, PantryQuantity(value: 400, unit: .milliliters))
        let product = try JSONDecoder().decode(
            CatalogIngredient.self, from: Data(#"{"id":"yogurt","name":"Йогурт","allowed_units":["ml"]}"#.utf8)
        )
        line.select(product)
        XCTAssertEqual(line.item?.ingredientID, "yogurt")
        XCTAssertNil(line.item?.quantity)
    }

    func testPhotoValidatesImageFormatAndByteLimit() throws {
        let photo = try Self.photo()
        XCTAssertEqual(photo.contentType, "image/png")
        XCTAssertEqual(photo.fileName, "photo.png")
        XCTAssertThrowsError(try RecognitionPhoto(data: Data("%PDF".utf8))) { error in
            XCTAssertEqual(error as? RecognitionPhoto.InvalidImage, .unsupported)
        }
        XCTAssertThrowsError(try RecognitionPhoto(data: Data(count: RecognitionPhoto.maxBytes + 1))) { error in
            XCTAssertEqual(error as? RecognitionPhoto.InvalidImage, .tooLarge)
        }
    }

    @MainActor
    private func makeModel(
        sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in },
        respond: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) async throws -> PhotoImportModel {
        let session = try SessionFixture.store(
            storage: SessionTestStorage(.active(SessionFixture.original)), respond: respond)
        await session.restore()
        let account = try XCTUnwrap(session.account)
        let pantry = PantryModel(repository: ProductsRepository(session: session, account: account))
        await pantry.reload()
        return PhotoImportModel(
            pantry: pantry, repository: RecognitionRepository(session: session, account: account, sleep: sleep))
    }

    private static func photo() throws -> RecognitionPhoto {
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC"
        return try RecognitionPhoto(data: XCTUnwrap(Data(base64Encoded: base64)))
    }

    private static func assertMultipart(_ request: URLRequest, photo: RecognitionPhoto, kind: String) throws {
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer old-access")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        let key = try XCTUnwrap(request.value(forHTTPHeaderField: "Idempotency-Key"))
        XCTAssertNotNil(UUID(uuidString: key))
        let header = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        let prefix = "multipart/form-data; boundary="
        XCTAssertTrue(header.hasPrefix(prefix))
        let boundary = header.dropFirst(prefix.count)
        var expected = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"kind\"\r\n\r\n\(kind)\r\n".utf8)
        expected.append(
            contentsOf: "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"photo.png\"\r\n"
                .utf8)
        expected.append(contentsOf: "Content-Type: image/png\r\n\r\n".utf8)
        expected.append(photo.data)
        expected.append(contentsOf: "\r\n--\(boundary)--\r\n".utf8)
        XCTAssertEqual(request.httpBody, expected)
    }

    private static func initialState(_ request: URLRequest) throws -> (Data, URLResponse) {
        switch request.url?.path {
        case "/api/v1/me/state": try SessionFixture.stateResponse(request)
        case "/api/v1/me/pantry": try pantry(request, version: 7)
        default:
            throw URLError(.unsupportedURL)
        }
    }

    private static func pantry(
        _ request: URLRequest, version: Int
    ) throws -> (Data, URLResponse) {
        try SessionFixture.response(
            request,
            body: [
                "state_version": version,
                "items": []
            ],
            etag: #""state-\#(version)""#
        )
    }

    private static func recognition(
        _ request: URLRequest, status: String, kind: String = "receipt", poll: Int = 1, retryAfter: String? = nil,
        lines: [[String: Any]] = [], retryableFailure: Bool = false
    ) throws -> (Data, URLResponse) {
        var body: [String: Any] = [
            "id": "job", "kind": kind, "status": status, "expires_at": "2030-01-01T00:00:00Z",
            "poll_after_seconds": poll, "items": lines, "failure": NSNull()
        ]
        if retryableFailure {
            body["failure"] = [
                "error": [
                    "code": "recognition_failed", "message": "Fixture error", "retryable": true,
                    "request_id": "00000000-0000-4000-8000-000000000001", "details": []
                ]
            ]
        }
        return try SessionFixture.response(
            request, status: request.httpMethod == "POST" ? 202 : 200, body: body, retryAfter: retryAfter)
    }

    private static func lines() -> [[String: Any]] {
        [
            [
                "line_id": "line-1", "raw_name": "Продукт 1", "status": "unmatched", "candidates": [],
                "suggested_quantity": NSNull()
            ],
            [
                "line_id": "line-2", "raw_name": "Продукт 2", "status": "matched",
                "candidates": [["ingredient_id": "milk", "name": "Молоко", "confidence": 0.9]],
                "suggested_quantity": ["value": 400, "unit": "ml"]
            ]
        ]
    }

    private static func imported(_ request: URLRequest, version: Int) throws -> (Data, URLResponse) {
        try SessionFixture.response(
            request,
            body: [
                "operation_id": "import", "recognition_id": "job", "state_version": version,
                "pantry": [["ingredient_id": "cheese", "name": "Сыр", "quantity": NSNull()]]
            ],
            etag: #""state-\#(version)""#
        )
    }

    fileprivate static func jsonBody(_ request: URLRequest) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? NSDictionary)
    }
}

private actor RecognitionTestTrace {
    private(set) var requests: [URLRequest] = []
    private(set) var delays: [Duration] = []

    func recordRequest(_ request: URLRequest) -> Int {
        requests.append(request)
        return requests.count
    }

    func recordDelay(_ delay: Duration) { delays.append(delay) }
}

private actor RecognitionImportLedger {
    private var keys: Set<String> = []
    private(set) var requests: [URLRequest] = []
    private(set) var items: [String] = []

    // Commit before dropping the first response, as when a connection dies after the write.
    func accept(_ request: URLRequest) throws -> Bool {
        requests.append(request)
        let key = try XCTUnwrap(request.value(forHTTPHeaderField: "Idempotency-Key"))
        guard keys.insert(key).inserted else { return false }
        let body = try PhotoImportTests.jsonBody(request)
        let imported = try XCTUnwrap(body["items"] as? [[String: Any]])
        items.append(contentsOf: imported.compactMap { $0["ingredient_id"] as? String })
        return true
    }
}
