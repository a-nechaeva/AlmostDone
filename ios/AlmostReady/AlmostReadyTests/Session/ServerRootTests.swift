import Foundation
import SwiftUI
import UIKit
import XCTest

@testable import AlmostReady

final class ServerRootTests: XCTestCase {
    @MainActor
    func testSignInOpensProductsOnlyAfterConfirmationAndLogoutReturnsToSignIn() async throws {
        let verificationStarted = SessionResponseGate()
        let allowVerification = SessionResponseGate()
        let storage = SessionTestStorage()
        let didLoadProducts = expectation(description: "Server products request from the mounted root")
        didLoadProducts.assertForOverFulfill = false
        let session = try SessionFixture.store(storage: storage) { request in
            switch request.url?.path {
            case "/api/v1/auth/yandex":
                return try SessionFixture.sessionResponse(request, SessionFixture.original)
            case "/api/v1/me/state":
                await verificationStarted.open()
                await allowVerification.wait()
                return try SessionFixture.stateResponse(request)
            case "/api/v1/me/pantry":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer old-access")
                didLoadProducts.fulfill()
                return try SessionFixture.response(
                    request, body: ["state_version": 7, "items": []], etag: #""state-7""#)
            case "/api/v1/auth/logout":
                return try SessionFixture.response(request, status: 204)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        let root = ServerRoot(session: session)
        XCTAssertEqual(root.destination, .session)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousWindow?.makeKey()
        }
        await session.restore()
        XCTAssertEqual(session.phase, .signedOut(nil))
        XCTAssertEqual(root.destination, .session)

        let signingIn = Task { await session.signIn() }
        await verificationStarted.wait()
        XCTAssertEqual(session.phase, .signingIn)
        XCTAssertEqual(root.destination, .session)
        await allowVerification.open()
        await signingIn.value

        XCTAssertEqual(root.destination, .products)
        let account = try XCTUnwrap(session.account)
        await fulfillment(of: [didLoadProducts], timeout: 10)

        let result = try await session.signOut()
        XCTAssertEqual(result, .revoked)
        XCTAssertEqual(root.destination, .session)
        XCTAssertEqual(session.phase, .signedOut(nil))
        XCTAssertFalse(session.isCurrent(account))
        XCTAssertNil(storage.stored)

        await session.signIn()
        XCTAssertEqual(root.destination, .products)
        XCTAssertNotEqual(session.account?.id, account.id)
    }

    @MainActor
    func testRestoreFailureStaysOnSessionScreen() async throws {
        let session = try SessionFixture.store(storage: SessionTestStorage(.active(SessionFixture.original))) { _ in
            throw URLError(.timedOut)
        }
        let root = ServerRoot(session: session)
        await session.restore()
        XCTAssertEqual(session.phase, .restoreFailed)
        XCTAssertEqual(root.destination, .session)
    }
}
