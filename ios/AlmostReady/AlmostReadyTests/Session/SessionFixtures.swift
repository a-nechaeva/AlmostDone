import Foundation
import XCTest

@testable import AlmostReady

struct SessionTestTransport: HTTPTransport {
    let respond: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await respond(request)
    }
}

@MainActor
final class SessionTestStorage: SessionStorage {
    var stored: StoredSession?
    private(set) var writes: [StoredSession] = []
    var didRemove: (() -> Void)?
    var removalFails = false
    private var removalPending = false

    init(_ stored: StoredSession? = nil) {
        self.stored = stored
    }

    func load() throws -> StoredSession? {
        if removalPending { try remove() }
        return stored
    }

    func save(_ session: StoredSession) throws {
        writes.append(session)
        stored = session
    }

    func remove() throws {
        removalPending = true
        if removalFails { throw SessionError.storageUnavailable }
        stored = nil
        removalPending = false
        didRemove?()
    }
}

@MainActor
final class SessionTestYandex: YandexAuthorizing {
    var result: Result<String, YandexAuthorizationError> = .success("mock-oauth")
    private(set) var calls = 0

    func oauthToken() async throws -> String {
        calls += 1
        return try result.get()
    }
}

actor SessionRequestRecorder {
    private(set) var paths: [String] = []

    func append(_ request: URLRequest) {
        paths.append(request.url?.path ?? "")
    }
}

actor SessionResponseGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}

enum SessionFixture {
    static let original = SessionTokens(userID: "fixture-user", accessToken: "old-access", refreshToken: "old-refresh")
    static let rotated = SessionTokens(userID: "fixture-user", accessToken: "new-access", refreshToken: "new-refresh")
    static let another = SessionTokens(userID: "other-user", accessToken: "other-access", refreshToken: "other-refresh")

    static let state = APIRequest(path: ["me", "state"])
    static let pantry = APIRequest(path: ["me", "pantry"])
    static let mutation = APIRequest(
        path: ["me", "pantry", "add"], method: .post,
        headers: .init(ifMatch: #""state-7""#, idempotencyKey: "00000000-0000-4000-8000-000000000002")
    )

    @MainActor
    static func store(
        storage: SessionTestStorage, sdk: SessionTestYandex? = nil,
        respond: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) throws -> SessionStore {
        let client = try APIClient(
            baseURL: XCTUnwrap(URL(string: "https://example.test")),
            transport: SessionTestTransport(respond: respond)
        )
        return SessionStore(client: client, yandex: sdk ?? SessionTestYandex(), storage: storage)
    }

    static func stateResponse(
        _ request: URLRequest, version: Int = 7, user: SessionTokens = original
    ) throws -> (Data, URLResponse) {
        try response(
            request,
            body: [
                "state_version": version,
                "catalog_version": "fixture-catalog",
                "user_id": user.userID
            ],
            etag: #""state-\#(version)""#
        )
    }

    static func sessionResponse(_ request: URLRequest, _ tokens: SessionTokens) throws -> (Data, URLResponse) {
        try response(
            request,
            body: [
                "user_id": tokens.userID,
                "token_type": "Bearer",
                "access_token": tokens.accessToken,
                "refresh_token": tokens.refreshToken,
                "expires_in": 900,
                "refresh_expires_in": 2_592_000
            ]
        )
    }

    static func error(
        _ request: URLRequest, status: Int = 401, code: String = "session_expired", retryAfter: String? = nil
    ) throws -> (Data, URLResponse) {
        try response(
            request, status: status,
            body: [
                "error": [
                    "code": code,
                    "message": "Fixture error",
                    "retryable": status == 429,
                    "request_id": "00000000-0000-4000-8000-000000000001",
                    "details": []
                ]
            ],
            retryAfter: retryAfter
        )
    }

    static func response(
        _ request: URLRequest, status: Int = 200, body: [String: Any]? = nil, etag: String? = nil,
        retryAfter: String? = nil
    ) throws -> (Data, URLResponse) {
        var headers: [String: String] = [:]
        headers["ETag"] = etag
        headers["Retry-After"] = retryAfter
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: XCTUnwrap(request.url), statusCode: status, httpVersion: nil,
                headerFields: headers
            )
        )
        return (try body.map { try JSONSerialization.data(withJSONObject: $0) } ?? Data(), response)
    }

    static func assertRequest(
        _ request: URLRequest, method: String, token: String? = nil, body: [String: String]? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(request.httpMethod, method, file: file, line: line)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"), token.map { "Bearer \($0)" },
            file: file, line: line
        )
        if let body {
            let actual = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String]
            XCTAssertEqual(actual, body, file: file, line: line)
        } else {
            XCTAssertNil(request.httpBody, file: file, line: line)
        }
    }
}
