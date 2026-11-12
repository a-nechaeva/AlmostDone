import XCTest

final class ProductsScreenshotTests: XCTestCase {
    @MainActor
    func testCaptureProducts() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()

        let title = app.staticTexts["root.title.products"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(title.isHittable)
        let summary = app.staticTexts["products.summary"]
        XCTAssertTrue(summary.isHittable)
        XCTAssertEqual(summary.label, "4 продукта · всё под рукой")
        XCTAssertTrue(app.staticTexts["root.brand"].isHittable)
        XCTAssertTrue(app.staticTexts["root.demo"].isHittable)
        let eggs = app.staticTexts["Яйца"]
        XCTAssertTrue(eggs.waitForExistence(timeout: 10))
        XCTAssertTrue(eggs.isHittable)
        let dishesLink = app.buttons["products.dishes"]
        XCTAssertTrue(dishesLink.waitForExistence(timeout: 10))
        XCTAssertTrue(dishesLink.isHittable)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "almostready-products"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
