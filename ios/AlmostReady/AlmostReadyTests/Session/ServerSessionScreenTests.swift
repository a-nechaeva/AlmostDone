import Foundation
import SwiftUI
import UIKit
import XCTest

@testable import AlmostReady

final class ServerSessionScreenTests: XCTestCase {
    @MainActor
    func testSignedOutScreenFitsAtDefaultSizeAndScrollsWithLargeText() async throws {
        let session = try SessionFixture.store(storage: SessionTestStorage()) { _ in
            XCTFail("The signed-out screen should not contact the server")
            throw URLError(.unsupportedURL)
        }
        await session.restore()
        XCTAssertEqual(session.phase, .signedOut(nil))

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = .light
        defer {
            window.isHidden = true
            previousWindow?.makeKey()
        }

        let standard = ServerSessionScreen()
            .environment(session)
            .environment(\.dynamicTypeSize, .large)
        window.rootViewController = UIHostingController(rootView: standard)
        window.makeKeyAndVisible()
        attachScreenshot(of: window, named: "almostready-login")

        let standardScroll = try XCTUnwrap(firstScrollView(in: window))
        XCTAssertGreaterThan(standardScroll.contentSize.height, 0)
        XCTAssertLessThanOrEqual(standardScroll.contentSize.height, standardScroll.bounds.height + 1)
        XCTAssertNotNil(UIFont(name: "Inter-Regular", size: 15))
        XCTAssertNotNil(UIFont(name: "Inter-Bold", size: 36))
        XCTAssertNotNil(UIImage(named: "LoginBowl"))

        let compact = ServerSessionScreen()
            .environment(session)
            .environment(\.dynamicTypeSize, .accessibility5)
            .frame(width: 320, height: 568)
        window.rootViewController = UIHostingController(rootView: compact)
        attachScreenshot(of: window, named: "almostready-login-large-text")

        let compactScroll = try XCTUnwrap(firstScrollView(in: window))
        XCTAssertLessThanOrEqual(compactScroll.bounds.width, 321)
        XCTAssertLessThanOrEqual(compactScroll.contentSize.width, compactScroll.bounds.width + 1)
        XCTAssertGreaterThan(compactScroll.contentSize.height, compactScroll.bounds.height)
    }

    @MainActor
    func testPendingSignInIgnoresDuplicatesAndFailureAllowsRetry() async throws {
        let sdk = SessionTestYandex()
        let requests = SessionRequestRecorder()
        let exchangeStarted = expectation(description: "First sign-in exchange started")
        let finishExchange = SessionResponseGate()
        let session = try SessionFixture.store(storage: SessionTestStorage(), sdk: sdk) { request in
            await requests.append(request)
            switch request.url?.path {
            case "/api/v1/auth/yandex":
                if await requests.paths.count == 1 {
                    exchangeStarted.fulfill()
                    await finishExchange.wait()
                    throw URLError(.timedOut)
                }
                return try SessionFixture.sessionResponse(request, SessionFixture.original)
            case "/api/v1/me/state":
                return try SessionFixture.stateResponse(request)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        await session.restore()

        let signIn = Task { await session.signIn() }
        await fulfillment(of: [exchangeStarted], timeout: 5)
        XCTAssertEqual(session.phase, .signingIn)

        await session.signIn()
        XCTAssertEqual(sdk.calls, 1)
        await finishExchange.open()
        await signIn.value

        XCTAssertEqual(session.phase, .signedOut(.signInFailed))
        await session.signIn()
        XCTAssertNotNil(session.account)
        XCTAssertEqual(sdk.calls, 2)
        let paths = await requests.paths
        XCTAssertEqual(paths, ["/api/v1/auth/yandex", "/api/v1/auth/yandex", "/api/v1/me/state"])
    }

    @MainActor
    private func attachScreenshot(of window: UIWindow, named name: String) {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for child in view.subviews {
            if let scrollView = firstScrollView(in: child) { return scrollView }
        }
        return nil
    }
}
