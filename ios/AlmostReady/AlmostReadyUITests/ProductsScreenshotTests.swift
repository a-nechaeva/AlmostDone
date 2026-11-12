import XCTest

final class ProductsScreenshotTests: XCTestCase {
    @MainActor
    func testCaptureProducts() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()

        XCTAssertTrue(app.staticTexts["root.title.products"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["root.brand"].isHittable)
        XCTAssertTrue(app.staticTexts["root.demo"].isHittable)
        let eggs = app.staticTexts["Яйца"]
        XCTAssertTrue(eggs.waitForExistence(timeout: 10))
        XCTAssertTrue(eggs.isHittable)
        let dishesLink = app.descendants(matching: .any)["products.dishes"].firstMatch
        XCTAssertTrue(dishesLink.waitForExistence(timeout: 10))
        XCTAssertTrue(dishesLink.isHittable)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "almostready-products"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
