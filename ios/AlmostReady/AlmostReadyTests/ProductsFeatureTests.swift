import XCTest

@testable import AlmostReady

final class ProductsFeatureTests: XCTestCase {
    @MainActor
    func testCatalogSearchIgnoresCaseAndSurroundingWhitespace() {
        let matches = ProductsSearch.matches("  сЫ \n", excluding: DemoData.initialProductIDs)
        XCTAssertEqual(matches.map(\.id), [DemoData.cheese.id])
        XCTAssertTrue(ProductsSearch.matches("нет такого", excluding: []).isEmpty)
    }

    @MainActor
    func testBlankQueryShowsOnlyProductsThatCanBeAdded() {
        let matches = ProductsSearch.matches("  ", excluding: DemoData.initialProductIDs)
        XCTAssertEqual(matches.map(\.id), [DemoData.cheese.id])
    }

    @MainActor
    func testCatalogSearchReflectsChangesToTheSharedPantry() async {
        let store = DemoStore()
        let cheese = DemoData.cheese

        XCTAssertEqual(ProductsSearch.matches("сыр", excluding: store.productIDs).map(\.id), [cheese.id])

        store.productIDs.insert(cheese.id)
        store.productIDs.insert(cheese.id)
        XCTAssertEqual(store.products.filter { $0.id == cheese.id }.count, 1)
        XCTAssertTrue(ProductsSearch.matches("сыр", excluding: store.productIDs).isEmpty)

        store.productIDs.remove(cheese.id)
        XCTAssertFalse(store.products.contains { $0.id == cheese.id })
        XCTAssertEqual(ProductsSearch.matches("сыр", excluding: store.productIDs).map(\.id), [cheese.id])
    }
}
