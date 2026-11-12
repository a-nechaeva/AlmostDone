import Foundation
import XCTest

@testable import AlmostReady

final class SessionStoreTests: XCTestCase {
    private typealias Fixture = SessionFixture

    @MainActor
    func testYandexSignInExchangesOAuthAndVerifiesServerBearerBeforeSaving() async throws {
        let storage = SessionTestStorage()
        let sdk = SessionTestYandex()
        let recorder = SessionRequestRecorder()
        let store = try Fixture.store(storage: storage, sdk: sdk) { request in
            await recorder.append(request)
            switch request.url?.path {
            case "/api/v1/auth/yandex":
                try Fixture.assertRequest(request, method: "POST", body: ["oauth_token": "mock-oauth"])
                return try Fixture.sessionResponse(request, Fixture.original)
            case "/api/v1/me/state":
                try Fixture.assertRequest(request, method: "GET", token: Fixture.original.accessToken)
                return try Fixture.stateResponse(request)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        await store.restore()
        XCTAssertEqual(store.phase, .signedOut(nil))
        await store.signIn()

        XCTAssertNotNil(store.account)
        XCTAssertEqual(store.revision?.etag, #""state-7""#)
        XCTAssertEqual(store.revision?.stateVersion, 7)
        XCTAssertEqual(storage.writes, [.active(Fixture.original)])
        XCTAssertEqual(sdk.calls, 1)
        let paths = await recorder.paths
        XCTAssertEqual(paths, ["/api/v1/auth/yandex", "/api/v1/me/state"])
    }

    @MainActor
    func testSDKCancelAndErrorDoNotContactServer() async throws {
        let storage = SessionTestStorage()
        let sdk = SessionTestYandex()
        let store = try Fixture.store(storage: storage, sdk: sdk) { _ in
            XCTFail("OAuth did not return a token")
            throw URLError(.unsupportedURL)
        }
        await store.restore()

        sdk.result = .failure(.cancelled)
        await store.signIn()
        XCTAssertEqual(store.phase, .signedOut(nil))

        sdk.result = .failure(.unavailable)
        await store.signIn()
        XCTAssertEqual(store.phase, .signedOut(.signInFailed))
        XCTAssertNil(storage.stored)
    }

    @MainActor
    func testSignInRejectsStateFromDifferentAccount() async throws {
        let storage = SessionTestStorage()
        let store = try Fixture.store(storage: storage) { request in
            switch request.url?.path {
            case "/api/v1/auth/yandex": try Fixture.sessionResponse(request, Fixture.original)
            case "/api/v1/me/state": try Fixture.stateResponse(request, user: Fixture.another)
            default: throw URLError(.unsupportedURL)
            }
        }

        await store.restore()
        await store.signIn()

        XCTAssertEqual(store.phase, .signedOut(.signInFailed))
        XCTAssertNil(store.revision)
        XCTAssertNil(storage.stored)
    }

    @MainActor
    func testRestoreVerifiesExistingPairWithoutYandex() async throws {
        let storage = SessionTestStorage(.active(Fixture.original))
        let sdk = SessionTestYandex()
        let store = try Fixture.store(storage: storage, sdk: sdk) { request in
            XCTAssertEqual(request.url?.path, "/api/v1/me/state")
            try Fixture.assertRequest(request, method: "GET", token: Fixture.original.accessToken)
            return try Fixture.stateResponse(request)
        }

        await store.restore()

        XCTAssertNotNil(store.account)
        XCTAssertEqual(store.revision?.stateVersion, 7)
        XCTAssertEqual(sdk.calls, 0)
        XCTAssertTrue(storage.writes.isEmpty)
    }

    @MainActor
    func testRestoreAfterInterruptedRotationRequiresSignInWithoutReusingRefresh() async throws {
        let storage = SessionTestStorage(.refreshing)
        let store = try Fixture.store(storage: storage) { _ in
            XCTFail("An interrupted rotation requires sign-in")
            throw URLError(.unsupportedURL)
        }

        await store.restore()

        XCTAssertEqual(store.phase, .signedOut(.signInRequired))
        XCTAssertNil(storage.stored)
    }

    @MainActor
    func testConcurrent401sShareOneRefreshAndRotateBothTokens() async throws {
        let storage = SessionTestStorage(.active(Fixture.original))
        let recorder = SessionRequestRecorder()
        let readsStarted = expectation(description: "Two requests use the old token")
        readsStarted.expectedFulfillmentCount = 2
        let rejectReads = SessionResponseGate()
        let refreshStarted = expectation(description: "Refresh started")
        let finishRefresh = SessionResponseGate()
        let store = try Fixture.store(storage: storage) { request in
            await recorder.append(request)
            switch request.url?.path {
            case "/api/v1/me/state":
                return try Fixture.stateResponse(request)
            case "/api/v1/me/pantry":
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer old-access" {
                    readsStarted.fulfill()
                    await rejectReads.wait()
                    return try Fixture.error(request)
                }
                try Fixture.assertRequest(request, method: "GET", token: Fixture.rotated.accessToken)
                return try Fixture.response(request)
            case "/api/v1/auth/refresh":
                try Fixture.assertRequest(request, method: "POST", body: ["refresh_token": "old-refresh"])
                refreshStarted.fulfill()
                await finishRefresh.wait()
                return try Fixture.sessionResponse(request, Fixture.rotated)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        await store.restore()
        let account = try XCTUnwrap(store.account)
        let first = Task { try await store.data(for: Fixture.pantry, account: account) }
        let second = Task { try await store.data(for: Fixture.pantry, account: account) }
        await fulfillment(of: [readsStarted], timeout: 5)
        await rejectReads.open()
        await fulfillment(of: [refreshStarted], timeout: 5)
        XCTAssertEqual(storage.stored, .refreshing)
        await finishRefresh.open()

        _ = try await first.value
        _ = try await second.value
        XCTAssertEqual(store.account, account)
        XCTAssertEqual(storage.writes, [.refreshing, .active(Fixture.rotated)])
        let paths = await recorder.paths
        XCTAssertEqual(paths.filter { $0 == "/api/v1/auth/refresh" }.count, 1)
        XCTAssertEqual(paths.filter { $0 == "/api/v1/me/pantry" }.count, 4)
    }

    @MainActor
    func testUnknownRefreshOutcomeForcesSignInAndNeverRetriesOldRefresh() async throws {
        for unavailable in [false, true] {
            let storage = SessionTestStorage(.active(Fixture.original))
            let recorder = SessionRequestRecorder()
            let store = try Fixture.store(storage: storage) { request in
                await recorder.append(request)
                switch request.url?.path {
                case "/api/v1/me/state":
                    return try Fixture.error(request)
                case "/api/v1/auth/refresh":
                    if unavailable {
                        return try Fixture.error(request, status: 503, code: "service_unavailable")
                    }
                    throw URLError(.timedOut)
                default:
                    throw URLError(.unsupportedURL)
                }
            }

            await store.restore()
            await store.restore()

            XCTAssertEqual(store.phase, .signedOut(.signInRequired))
            XCTAssertNil(storage.stored)
            XCTAssertNil(store.revision)
            let paths = await recorder.paths
            XCTAssertEqual(paths, ["/api/v1/me/state", "/api/v1/auth/refresh"])
        }
    }

    @MainActor
    func testLate401AndRestartRespectRefreshRetryAfter() async throws {
        let storage = SessionTestStorage(.active(Fixture.original))
        let recorder = SessionRequestRecorder()
        let lateRead = APIRequest(path: ["me", "favorites"])
        let lateReadStarted = expectation(description: "Second request sent with the old token")
        let finishLateRead = SessionResponseGate()
        let store = try Fixture.store(storage: storage) { request in
            await recorder.append(request)
            switch request.url?.path {
            case "/api/v1/me/state":
                return try Fixture.stateResponse(request)
            case "/api/v1/me/favorites":
                lateReadStarted.fulfill()
                await finishLateRead.wait()
                return try Fixture.error(request)
            case "/api/v1/me/pantry":
                return try Fixture.error(request)
            case "/api/v1/auth/refresh":
                return try Fixture.error(request, status: 429, code: "rate_limited", retryAfter: "60")
            default:
                throw URLError(.unsupportedURL)
            }
        }
        await store.restore()
        let account = try XCTUnwrap(store.account)
        let late = Task { try await store.data(for: lateRead, account: account) }
        await fulfillment(of: [lateReadStarted], timeout: 5)

        do {
            _ = try await store.data(for: Fixture.pantry, account: account)
            XCTFail("The server rate-limited refresh")
        } catch let error as APIClientError {
            XCTAssertEqual(error.metadata?.retryAfter, "60")
        }
        await finishLateRead.open()
        do {
            _ = try await late.value
            XCTFail("The late 401 must not start another refresh")
        } catch SessionError.refreshRateLimited(let until) {
            XCTAssertGreaterThan(until, Date.now)
        }
        let paths = await recorder.paths
        XCTAssertEqual(paths.filter { $0 == "/api/v1/auth/refresh" }.count, 1)

        let restarted = try Fixture.store(storage: storage) { request in
            XCTAssertEqual(request.url?.path, "/api/v1/me/state")
            return try Fixture.error(request)
        }
        await restarted.restore()
        XCTAssertEqual(restarted.phase, .restoreFailed)
    }

    @MainActor
    func testSecond401StopsWithoutAnotherRefresh() async throws {
        let storage = SessionTestStorage(.active(Fixture.original))
        let recorder = SessionRequestRecorder()
        let store = try Fixture.store(storage: storage) { request in
            await recorder.append(request)
            switch request.url?.path {
            case "/api/v1/me/state", "/api/v1/me/pantry": return try Fixture.error(request)
            case "/api/v1/auth/refresh": return try Fixture.sessionResponse(request, Fixture.rotated)
            default: throw URLError(.unsupportedURL)
            }
        }

        await store.restore()

        XCTAssertEqual(store.phase, .signedOut(.signInRequired))
        XCTAssertNil(storage.stored)
        let paths = await recorder.paths
        XCTAssertEqual(paths, ["/api/v1/me/state", "/api/v1/auth/refresh", "/api/v1/me/state"])
    }

    @MainActor
    func testMutationTimeoutAnd401AreNeverAutomaticallyReplayed() async throws {
        for rejected in [false, true] {
            let storage = SessionTestStorage(.active(Fixture.original))
            let recorder = SessionRequestRecorder()
            let store = try Fixture.store(storage: storage) { request in
                await recorder.append(request)
                switch request.url?.path {
                case "/api/v1/me/state": return try Fixture.stateResponse(request)
                case "/api/v1/auth/refresh": return try Fixture.sessionResponse(request, Fixture.rotated)
                case "/api/v1/me/pantry/add":
                    XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), #""state-7""#)
                    XCTAssertEqual(
                        request.value(forHTTPHeaderField: "Idempotency-Key"),
                        "00000000-0000-4000-8000-000000000002"
                    )
                    if rejected { return try Fixture.error(request) }
                    throw URLError(.timedOut)
                default: throw URLError(.unsupportedURL)
                }
            }
            await store.restore()
            let account = try XCTUnwrap(store.account)

            do {
                _ = try await store.data(for: Fixture.mutation, account: account)
                XCTFail("The original mutation error must be delivered")
            } catch let error as APIClientError {
                if rejected {
                    XCTAssertEqual(error.metadata?.statusCode, 401)
                } else if case .network(let code) = error {
                    XCTAssertEqual(code, .timedOut)
                } else {
                    XCTFail("Expected a mutation timeout")
                }
            }
            let paths = await recorder.paths
            XCTAssertEqual(paths.filter { $0 == "/api/v1/me/pantry/add" }.count, 1)
            XCTAssertEqual(paths.filter { $0 == "/api/v1/auth/refresh" }.count, rejected ? 1 : 0)
        }
    }
}
