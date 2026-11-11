import Foundation
import XCTest

@testable import AlmostReady

final class ShoppingFeatureTests: XCTestCase {
    @MainActor
    func testPurchaseAndRepeatedUndoUpdateTheRemainingTotal() {
        var shopping = ShoppingState()
        let id = ShoppingDemoPlan.cheese.id

        XCTAssertEqual(shopping.estimatedRemainingTotal, 230)
        XCTAssertEqual(shopping.setPurchased(true, id: id)?.isPurchased, true)
        XCTAssertEqual(shopping.estimatedRemainingTotal, 0)
        XCTAssertEqual(shopping.setPurchased(false, id: id)?.isPurchased, false)
        XCTAssertEqual(shopping.setPurchased(false, id: id)?.isPurchased, false)
        XCTAssertEqual(shopping.estimatedRemainingTotal, 230)
    }

    @MainActor
    func testUnknownPriceLeavesTheTotalUnknownUntilItemIsPurchased() {
        var shopping = ShoppingState(
            items: [
                ShoppingDemoPlan.cheese,
                ShoppingItem(id: "tomatoes", name: "Томаты", quantity: "2 шт.", estimatedPrice: nil)
            ]
        )

        XCTAssertNil(shopping.estimatedRemainingTotal)
        shopping.setPurchased(true, id: "tomatoes")
        XCTAssertEqual(shopping.estimatedRemainingTotal, 230)
    }

    @MainActor
    func testDemoPlanAddsAnItemToAnEmptyListAndKeepsTheBudgetDraft() {
        var shopping = ShoppingState(items: [])
        shopping.budgetInput = "600,50"
        XCTAssertTrue(shopping.items.isEmpty)
        XCTAssertNil(shopping.setPurchased(true, id: ShoppingDemoPlan.cheese.id))

        shopping.addDemoPlan()
        shopping.setPurchased(true, id: ShoppingDemoPlan.cheese.id)
        shopping.addDemoPlan()

        XCTAssertEqual(shopping.items.map(\.id), [ShoppingDemoPlan.cheese.id])
        XCTAssertEqual(shopping.items.first?.isPurchased, true)
        XCTAssertEqual(shopping.budgetInput, "600,50")
    }

    @MainActor
    func testBudgetRejectsBlankZeroAndMalformedAmounts() {
        XCTAssertEqual(ShoppingBudgetResult.evaluate(" \n"), .failure(.empty))
        XCTAssertEqual(ShoppingBudgetResult.evaluate("0,00"), .failure(.zero))
        for input in ["-1", "1e3", "230 ₽", "230,001", "2 30", "230,", "999999999999999999999999999999999"] {
            XCTAssertEqual(ShoppingBudgetResult.evaluate(input), .failure(.invalid), input)
        }
    }

    @MainActor
    func testDemoPlanUsesTheFixedPackagePriceAsTheThreshold() {
        XCTAssertEqual(ShoppingBudgetResult.evaluate("200"), .success(.unavailable(budget: 200)))
        XCTAssertEqual(
            ShoppingBudgetResult.evaluate("229,99"),
            .success(.unavailable(budget: Decimal(22_999) / 100))
        )
        XCTAssertEqual(ShoppingBudgetResult.evaluate("230"), .success(.example(budget: 230)))
        XCTAssertEqual(
            ShoppingBudgetResult.evaluate(" 1 000.50 "),
            .success(.example(budget: Decimal(100_050) / 100))
        )
    }
}
