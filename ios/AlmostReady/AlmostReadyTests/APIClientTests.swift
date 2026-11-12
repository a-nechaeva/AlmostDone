import Foundation
import XCTest

@testable import AlmostReady

final class APIClientTests: XCTestCase {
    private struct StubTransport: HTTPTransport {
        let respond: @Sendable (URLRequest) throws -> (Data, URLResponse)

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            try respond(request)
        }
    }

    private struct StateDTO: Decodable, Sendable {
        let stateVersion: Int
        let catalogVersion: String
        let userID: String

        private enum CodingKeys: String, CodingKey {
            case stateVersion = "state_version"
            case catalogVersion = "catalog_version"
            case userID = "user_id"
        }
    }

    private struct PantryAddDTO: Encodable, Sendable {
        struct Quantity: Encodable, Sendable {
            let value: Int
            let unit: String
        }

        let ingredientID: String
        let quantity: Quantity

        private enum CodingKeys: String, CodingKey {
            case ingredientID = "ingredient_id"
            case quantity
        }
    }

    private struct PantryDTO: Decodable, Sendable {
        struct Item: Decodable, Sendable {
            let name: String
        }

        let stateVersion: Int
        let items: [Item]

        private enum CodingKeys: String, CodingKey {
            case stateVersion = "state_version"
            case items
        }
    }

    func testProtectedStateReturnsTypedJSONAndHeaders() async throws {
        let body = Data(#"{"state_version":7,"catalog_version":"catalog-1","user_id":"user-1"}"#.utf8)
        let client = try makeClient { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.test/api/v1/me/state")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertNil(request.httpBody)
            return try Self.http(
                request,
                body: body,
                headers: ["eTAG": #""state-7""#, "content-type": "application/json; charset=utf-8"]
            )
        }

        let response = try await client.json(
            StateDTO.self,
            for: APIRequest(path: ["me", "state"], headers: .init(bearerToken: "test-access-token"))
        )

        XCTAssertEqual(response.value.stateVersion, 7)
        XCTAssertEqual(response.value.catalogVersion, "catalog-1")
        XCTAssertEqual(response.value.userID, "user-1")
        XCTAssertEqual(response.metadata.statusCode, 200)
        XCTAssertEqual(response.metadata.etag, #""state-7""#)
        XCTAssertEqual(response.metadata.contentType, "application/json; charset=utf-8")
        XCTAssertNil(response.metadata.retryAfter)
    }

    func testPantryMutationSendsJSONAndPerRequestHeaders() async throws {
        let idempotencyKey = "00000000-0000-4000-8000-000000000002"
        let body = Data(
            #"{"state_version":8,"items":[{"ingredient_id":"rice","name":"Рис","quantity":{"value":100,"unit":"g"}}]}"#
                .utf8
        )
        let client = try makeClient(timeout: 12) { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.test/api/v1/me/pantry/add")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.timeoutInterval, 12)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), #""state-7""#)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), idempotencyKey)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let actualBody = try XCTUnwrap(request.httpBody)
            let expectedBody = Data(#"{"ingredient_id":"rice","quantity":{"unit":"g","value":100}}"#.utf8)
            let actual = try XCTUnwrap(JSONSerialization.jsonObject(with: actualBody) as? NSDictionary)
            let expected = try XCTUnwrap(JSONSerialization.jsonObject(with: expectedBody) as? NSDictionary)
            XCTAssertEqual(actual, expected)
            return try Self.http(request, body: body, headers: ["ETag": #""state-8""#])
        }

        let request = APIRequest(
            path: ["me", "pantry", "add"],
            method: .post,
            headers: .init(bearerToken: "test-access-token", ifMatch: #""state-7""#, idempotencyKey: idempotencyKey),
            jsonBody: PantryAddDTO(ingredientID: "rice", quantity: .init(value: 100, unit: "g"))
        )
        let response = try await client.json(PantryDTO.self, for: request)

        XCTAssertEqual(response.value.stateVersion, 8)
        XCTAssertEqual(response.value.items.map(\.name), ["Рис"])
        XCTAssertEqual(response.metadata.etag, #""state-8""#)
    }

    func testQueryPreservesUnicodeAndReservedCharacters() async throws {
        let client = try makeClient(baseURL: "https://example.test/gateway/") { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://example.test/gateway/api/v1/ingredients?q=%D1%81%D1%8B%D1%80%20%2B%26%3D%23&cursor=a%2Bb%2F%3D"
            )
            return try Self.http(request, body: Data("{}".utf8))
        }

        _ = try await client.json(
            [String: String].self,
            for: APIRequest(
                path: ["ingredients"],
                query: [URLQueryItem(name: "q", value: "сыр +&=#"), URLQueryItem(name: "cursor", value: "a+b/=")]
            )
        )
    }

    func testPublicPhotoUsesSinglePrefixAndEncodesRecipeID() async throws {
        let image = Data([0xff, 0xd8, 0xff, 0x00])
        let client = try makeClient(baseURL: "https://example.test/gateway/%61pi/v1/") { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://example.test/gateway/api/v1/recipes/folder%2Fpart%3F%23%252F/photo"
            )
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "If-Match"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Idempotency-Key"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
            return try Self.http(request, body: image, headers: ["Content-Type": "image/jpeg"])
        }

        let response = try await client.data(for: APIRequest(path: ["recipes", "folder/part?#%2F", "photo"]))

        XCTAssertEqual(response.value, image)
        XCTAssertEqual(response.metadata.statusCode, 200)
        XCTAssertEqual(response.metadata.contentType, "image/jpeg")
    }

    func testInvalidBasePrefixIsRejected() {
        for path in ["/api/v1/api/v1/", "/api/v1/gateway/"] {
            XCTAssertThrowsError(
                try makeClient(baseURL: "https://example.test" + path) { _ in
                    throw URLError(.badURL)
                }
            ) { error in
                guard case APIClientError.invalidConfiguration = error else {
                    return XCTFail("Expected an invalid base URL")
                }
            }
        }
    }

    func testAlreadyPrefixedRequestPathIsRejected() async throws {
        let client = try makeClient { _ in
            XCTFail("Invalid paths must not reach the transport")
            throw URLError(.badURL)
        }

        do {
            _ = try await client.json(StateDTO.self, for: APIRequest(path: ["api", "v1", "me", "state"]))
            XCTFail("Expected an invalid request path")
        } catch APIClientError.invalidRequest {
        }
    }

    func testNoContentKeepsETag() async throws {
        let client = try makeClient { request in
            XCTAssertEqual(request.url?.path, "/api/v1/auth/logout")
            XCTAssertEqual(request.httpMethod, "POST")
            return try Self.http(request, status: 204, headers: ["ETag": #""state-7""#])
        }

        let response = try await client.empty(
            for: APIRequest(path: ["auth", "logout"], method: .post, headers: .init(bearerToken: "test-access-token"))
        )

        XCTAssertEqual(response.metadata.statusCode, 204)
        XCTAssertEqual(response.metadata.etag, #""state-7""#)
    }

    func testValidationErrorDecodesEnvelopeAndDetails() async throws {
        let body = Data(
            """
            {"error":{
                "code":"validation_error","message":"Синтетический пример ошибки","retryable":false,
                "request_id":"00000000-0000-4000-8000-000000000001",
                "details":[
                    {"field":"items[0].quantity","code":"invalid_quantity","message":"Укажите положительное количество"}
                ]
            }}
            """.utf8
        )
        let client = try makeClient { request in
            try Self.http(request, status: 422, body: body, headers: ["Content-Type": "application/json"])
        }

        do {
            _ = try await client.json(PantryDTO.self, for: APIRequest(path: ["me", "pantry", "add"], method: .post))
            XCTFail("Expected a server validation error")
        } catch APIClientError.server(let error, let metadata) {
            XCTAssertEqual(metadata.statusCode, 422)
            XCTAssertEqual(metadata.contentType, "application/json")
            XCTAssertEqual(error.code, "validation_error")
            XCTAssertEqual(error.message, "Синтетический пример ошибки")
            XCTAssertFalse(error.retryable)
            XCTAssertEqual(error.requestID, "00000000-0000-4000-8000-000000000001")
            let detail = try XCTUnwrap(error.details.first)
            XCTAssertEqual(error.details.count, 1)
            XCTAssertEqual(detail.field, "items[0].quantity")
            XCTAssertEqual(detail.code, "invalid_quantity")
            XCTAssertEqual(detail.message, "Укажите положительное количество")
        }
    }

    func testRateLimitKeepsRetryAfter() async throws {
        let body = Data(
            """
            {"error":{
                "code":"rate_limited","message":"Синтетический пример ошибки","retryable":true,
                "request_id":"00000000-0000-4000-8000-000000000001","details":[]
            }}
            """.utf8
        )
        let client = try makeClient { request in
            try Self.http(request, status: 429, body: body, headers: ["retry-after": "2"])
        }

        do {
            _ = try await client.json(PantryDTO.self, for: APIRequest(path: ["me", "pantry"]))
            XCTFail("Expected a rate limit error")
        } catch APIClientError.server(let error, let metadata) {
            XCTAssertEqual(metadata.statusCode, 429)
            XCTAssertEqual(metadata.retryAfter, "2")
            XCTAssertEqual(error.code, "rate_limited")
            XCTAssertTrue(error.retryable)
            XCTAssertTrue(error.details.isEmpty)
        }
    }

    func testUnauthorizedReturnsStatusAndServerCode() async throws {
        let body = Data(
            """
            {"error":{
                "code":"session_expired","message":"Синтетический пример ошибки","retryable":false,
                "request_id":"00000000-0000-4000-8000-000000000001","details":[]
            }}
            """.utf8
        )
        let client = try makeClient { request in
            XCTAssertEqual(request.url?.path, "/api/v1/me/state")
            return try Self.http(request, status: 401, body: body)
        }

        do {
            _ = try await client.json(
                StateDTO.self,
                for: APIRequest(path: ["me", "state"], headers: .init(bearerToken: "expired-test-token"))
            )
            XCTFail("Expected an unauthorized response")
        } catch APIClientError.server(let error, let metadata) {
            XCTAssertEqual(metadata.statusCode, 401)
            XCTAssertEqual(error.code, "session_expired")
        }
    }

    func testUnexpectedBodyPreservesHTTPMetadata() async throws {
        for status in [200, 401] {
            let client = try makeClient { request in
                try Self.http(
                    request, status: status, body: Data("<html/>".utf8), headers: ["Content-Type": "text/html"]
                )
            }

            do {
                _ = try await client.json(StateDTO.self, for: APIRequest(path: ["me", "state"]))
                XCTFail("Expected an invalid response")
            } catch APIClientError.invalidResponse(let metadata) {
                XCTAssertEqual(metadata?.statusCode, status)
                XCTAssertEqual(metadata?.contentType, "text/html")
            }
        }
    }

    func testNonHTTPResponseIsInvalid() async throws {
        let client = try makeClient { request in
            let response = URLResponse(
                url: try XCTUnwrap(request.url), mimeType: nil, expectedContentLength: 0, textEncodingName: nil
            )
            return (Data(), response)
        }

        do {
            _ = try await client.data(for: APIRequest(path: ["recipes", "rice", "photo"]))
            XCTFail("Expected an invalid response")
        } catch APIClientError.invalidResponse(let metadata) {
            XCTAssertNil(metadata)
        }
    }

    func testNetworkFailureAndTimeoutPreserveSystemCode() async throws {
        for code: URLError.Code in [.notConnectedToInternet, .timedOut] {
            let client = try makeClient { _ in throw URLError(code) }

            do {
                _ = try await client.json(StateDTO.self, for: APIRequest(path: ["me", "state"]))
                XCTFail("Expected a network failure")
            } catch APIClientError.network(let actual) {
                XCTAssertEqual(actual, code)
            }
        }
    }

    func testSystemCancellationIsDistinctFromNetworkFailure() async throws {
        let client = try makeClient { _ in throw URLError(.cancelled) }

        do {
            _ = try await client.json(StateDTO.self, for: APIRequest(path: ["me", "state"]))
            XCTFail("Expected cancellation")
        } catch APIClientError.cancelled {
        }
    }

    private func makeClient(
        baseURL: String = "https://example.test",
        timeout: TimeInterval = 30,
        respond: @escaping @Sendable (URLRequest) throws -> (Data, URLResponse)
    ) throws -> APIClient {
        try APIClient(
            baseURL: XCTUnwrap(URL(string: baseURL)),
            timeout: timeout,
            transport: StubTransport(respond: respond)
        )
    }

    private static func http(
        _ request: URLRequest,
        status: Int = 200,
        body: Data = Data(),
        headers: [String: String] = [:]
    ) throws -> (Data, URLResponse) {
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )
        )
        return (body, response)
    }
}
