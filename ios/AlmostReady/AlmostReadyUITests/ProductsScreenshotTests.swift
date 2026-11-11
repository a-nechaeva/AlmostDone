import XCTest

final class ProductsScreenshotTests: XCTestCase {
    @MainActor
    func testCaptureProducts() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Мои продукты"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Яйца"].waitForExistence(timeout: 10))
        let dishesLink = app.descendants(matching: .any)["products.dishes"].firstMatch
        XCTAssertTrue(dishesLink.waitForExistence(timeout: 10))

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "almostready-products"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
