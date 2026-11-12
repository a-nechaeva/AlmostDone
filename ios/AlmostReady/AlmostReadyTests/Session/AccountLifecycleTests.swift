import Foundation
import XCTest

@testable import AlmostReady

final class AccountLifecycleTests: XCTestCase {
    private typealias Fixture = SessionFixture

    @MainActor
    func testLogoutClearsLocalAccountFor204And401() async throws {
        for (status, expected): (Int, LogoutResult) in [(204, .revoked), (401, .alreadyUnauthorized)] {
            let storage = SessionTestStorage(.active(Fixture.original))
            let store = try Fixture.store(storage: storage) { request in
                switch request.url?.path {
                case "/api/v1/me/state":
                    return try Fixture.stateResponse(request)
                case "/api/v1/auth/logout":
                    try Fixture.assertRequest(request, method: "POST", token: Fixture.original.accessToken)
                    if status == 401 { return try Fixture.error(request) }
                    return try Fixture.response(request, status: 204, etag: #""state-7""#)
                default:
                    throw URLError(.unsupportedURL)
                }
            }
            await store.restore()
            let account = try XCTUnwrap(store.account)

            let result = try await store.signOut()

            XCTAssertEqual(result, expected)
            let notice: SessionStore.Notice? = status == 401 ? .revocationUnconfirmed : nil
            XCTAssertEqual(store.phase, .signedOut(notice))
            XCTAssertFalse(store.isCurrent(account))
            XCTAssertNil(storage.stored)
            XCTAssertNil(store.revision)
        }
    }

    @MainActor
    func testFailedRevocationIsReportedAfterLocalLogout() async throws {
        let storage = SessionTestStorage(.active(Fixture.original))
        let store = try Fixture.store(storage: storage) { request in
            switch request.url?.path {
            case "/api/v1/me/state": try Fixture.stateResponse(request)
            case "/api/v1/auth/logout": throw URLError(.timedOut)
            default: throw URLError(.unsupportedURL)
            }
        }
        await store.restore()

        let result = try await store.signOut()

        XCTAssertEqual(result, .revocationUnconfirmed)
        XCTAssertEqual(store.phase, .signedOut(.revocationUnconfirmed))
        XCTAssertNil(storage.stored)
        XCTAssertNil(store.revision)
    }

    @MainActor
    func testLogoutDuringRefreshRevokesRotatedFamilyWithoutInstallingIt() async throws {
        let storage = SessionTestStorage(.active(Fixture.original))
        let refreshStarted = expectation(description: "Rotation request sent")
        let finishRefresh = SessionResponseGate()
        let store = try Fixture.store(storage: storage) { request in
            switch request.url?.path {
            case "/api/v1/me/state":
                return try Fixture.stateResponse(request)
            case "/api/v1/me/pantry":
                try Fixture.assertRequest(request, method: "GET", token: Fixture.original.accessToken)
                return try Fixture.error(request)
            case "/api/v1/auth/refresh":
                refreshStarted.fulfill()
                await finishRefresh.wait()
                return try Fixture.sessionResponse(request, Fixture.rotated)
            case "/api/v1/auth/logout":
                try Fixture.assertRequest(request, method: "POST", token: Fixture.rotated.accessToken)
                return try Fixture.response(request, status: 204)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        await store.restore()
        let account = try XCTUnwrap(store.account)
        let read = Task { try await store.data(for: Fixture.pantry, account: account) }
        await fulfillment(of: [refreshStarted], timeout: 5)
        let logoutStarted = expectation(description: "Local account invalidated")
        storage.didRemove = { logoutStarted.fulfill() }
        let logout = Task { try await store.signOut() }
        await fulfillment(of: [logoutStarted], timeout: 5)
        XCTAssertFalse(store.isCurrent(account))
        XCTAssertNil(storage.stored)
        await finishRefresh.open()

        let outcome = try await logout.value
        XCTAssertEqual(outcome, .revoked)
        do {
            _ = try await read.value
            XCTFail("The stale read must not retry")
        } catch SessionError.sessionChanged {
        }
        XCTAssertEqual(storage.writes, [.refreshing])
        XCTAssertNil(storage.stored)
        XCTAssertNil(store.account)
    }

    @MainActor
    func testLogoutDuringTimedOutRotationReportsUnconfirmedRevocation() async throws {
        let storage = SessionTestStorage(.active(Fixture.original))
        let refreshStarted = expectation(description: "Rotation request sent")
        let finishRefresh = SessionResponseGate()
        let store = try Fixture.store(storage: storage) { request in
            switch request.url?.path {
            case "/api/v1/me/state": return try Fixture.stateResponse(request)
            case "/api/v1/me/pantry": return try Fixture.error(request)
            case "/api/v1/auth/refresh":
                refreshStarted.fulfill()
                await finishRefresh.wait()
                throw URLError(.timedOut)
            case "/api/v1/auth/logout":
                try Fixture.assertRequest(request, method: "POST", token: Fixture.original.accessToken)
                return try Fixture.error(request)
            default: throw URLError(.unsupportedURL)
            }
        }
        await store.restore()
        let account = try XCTUnwrap(store.account)
        let read = Task { try await store.data(for: Fixture.pantry, account: account) }
        await fulfillment(of: [refreshStarted], timeout: 5)

        let logoutStarted = expectation(description: "Local account invalidated")
        storage.didRemove = { logoutStarted.fulfill() }
        let logout = Task { try await store.signOut() }
        await fulfillment(of: [logoutStarted], timeout: 5)
        await finishRefresh.open()

        let result = try await logout.value
        XCTAssertEqual(result, .alreadyUnauthorized)
        XCTAssertEqual(store.phase, .signedOut(.revocationUnconfirmed))
        XCTAssertNil(storage.stored)
        do {
            _ = try await read.value
            XCTFail("The stale read must not retry")
        } catch SessionError.sessionChanged {
        }
    }

    @MainActor
    func testRestartRetriesPendingLocalCleanupWithoutUsingOldCredentials() async throws {
        let storage = SessionTestStorage(.active(Fixture.original))
        let store = try Fixture.store(storage: storage) { request in
            switch request.url?.path {
            case "/api/v1/me/state": try Fixture.stateResponse(request)
            case "/api/v1/auth/logout": throw URLError(.timedOut)
            default: throw URLError(.unsupportedURL)
            }
        }
        await store.restore()
        storage.removalFails = true

        do {
            _ = try await store.signOut()
            XCTFail("A Keychain deletion failure must be reported")
        } catch SessionError.storageUnavailable {
        }
        XCTAssertEqual(store.phase, .signedOut(.storageUnavailable))
        XCTAssertEqual(storage.stored, .active(Fixture.original))

        let restarted = try Fixture.store(storage: storage) { _ in
            XCTFail("A pending local logout must not verify old credentials")
            throw URLError(.unsupportedURL)
        }
        await restarted.restore()
        XCTAssertEqual(restarted.phase, .restoreFailed)
        storage.removalFails = false
        await restarted.restore()

        XCTAssertEqual(restarted.phase, .signedOut(nil))
        XCTAssertNil(storage.stored)
    }

    @MainActor
    func testLateProtectedResponseCannotApplyToNewAccount() async throws {
        let storage = SessionTestStorage(.active(Fixture.original))
        let readStarted = expectation(description: "Old account read sent")
        let finishRead = SessionResponseGate()
        let store = try Fixture.store(storage: storage) { request in
            switch request.url?.path {
            case "/api/v1/me/state":
                let isNewAccount = request.value(forHTTPHeaderField: "Authorization") == "Bearer other-access"
                return try Fixture.stateResponse(
                    request, version: isNewAccount ? 1 : 7, user: isNewAccount ? Fixture.another : Fixture.original
                )
            case "/api/v1/me/pantry":
                try Fixture.assertRequest(request, method: "GET", token: Fixture.original.accessToken)
                readStarted.fulfill()
                await finishRead.wait()
                return try Fixture.response(request, etag: #""state-99""#)
            case "/api/v1/auth/yandex":
                return try Fixture.sessionResponse(request, Fixture.another)
            case "/api/v1/auth/logout":
                return try Fixture.response(request, status: 204)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        await store.restore()
        let oldAccount = try XCTUnwrap(store.account)
        let read = Task { try await store.data(for: Fixture.pantry, account: oldAccount) }
        await fulfillment(of: [readStarted], timeout: 5)
        _ = try await store.signOut()
        await store.signIn()
        await finishRead.open()

        do {
            _ = try await read.value
            XCTFail("The old account's response must be discarded")
        } catch SessionError.sessionChanged {
        }
        let newAccount = try XCTUnwrap(store.account)
        XCTAssertNotEqual(newAccount, oldAccount)
        XCTAssertEqual(store.revision?.stateVersion, 1)
        XCTAssertEqual(storage.stored, .active(Fixture.another))
        do {
            _ = try await store.data(for: Fixture.pantry, account: oldAccount)
            XCTFail("An old repository cannot send a request using the new account")
        } catch SessionError.sessionChanged {
        }
    }

    @MainActor
    func testLateLoginResponseDoesNotRecreateSignedOutSession() async throws {
        let storage = SessionTestStorage()
        let loginStarted = expectation(description: "OAuth exchange sent")
        let finishLogin = SessionResponseGate()
        let store = try Fixture.store(storage: storage) { request in
            guard request.url?.path == "/api/v1/auth/yandex" else {
                XCTFail("No verification after local logout")
                throw URLError(.unsupportedURL)
            }
            loginStarted.fulfill()
            await finishLogin.wait()
            return try Fixture.sessionResponse(request, Fixture.original)
        }

        await store.restore()
        let login = Task { await store.signIn() }
        await fulfillment(of: [loginStarted], timeout: 5)
        _ = try await store.signOut()
        await finishLogin.open()
        await login.value

        XCTAssertEqual(store.phase, .signedOut(nil))
        XCTAssertNil(storage.stored)
        XCTAssertTrue(storage.writes.isEmpty)
    }

    @MainActor
    func testConfirmedMutationsShareMonotonicRevision() async throws {
        let storage = SessionTestStorage(.active(Fixture.original))
        let store = try Fixture.store(storage: storage) { request in
            switch request.url?.path {
            case "/api/v1/me/state":
                return try Fixture.stateResponse(request)
            case "/api/v1/me/pantry/add":
                return try Fixture.response(request, etag: #""state-9""#)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        await store.restore()
        let account = try XCTUnwrap(store.account)
        let older = try XCTUnwrap(store.revision)

        let mutation = try await store.empty(for: Fixture.mutation, account: account)
        try store.confirmMutation(mutation.metadata, stateVersion: 9, account: account)
        XCTAssertThrowsError(try store.confirmMutation(mutation.metadata, stateVersion: 10, account: account))
        let reloaded = try await store.reloadRevision(for: account)

        XCTAssertEqual(store.revision?.stateVersion, 9)
        XCTAssertEqual(reloaded, store.revision)
        XCTAssertEqual(older.stateVersion, 7)
    }
}
