import XCTest

@testable import AlmostReady

final class DemoStoreTests: XCTestCase {
    @MainActor
    func testChangingPantryUpdatesMissingIngredients() throws {
        let store = DemoStore()
        let pasta = try XCTUnwrap(store.recipe(id: "tomato-cheese-pasta"))

        XCTAssertEqual(store.missingIngredients(for: pasta).map(\.id), ["cheese"])

        store.productIDs.insert("cheese")
        XCTAssertTrue(store.missingIngredients(for: pasta).isEmpty)

        store.productIDs.remove("tomatoes")
        XCTAssertEqual(store.missingIngredients(for: pasta).map(\.id), ["tomatoes"])
    }
}
