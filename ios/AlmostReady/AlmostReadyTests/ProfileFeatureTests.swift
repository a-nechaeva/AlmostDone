import XCTest

@testable import AlmostReady

final class ProfileFeatureTests: XCTestCase {
    @MainActor
    func testSaveAppliesAllDraftValuesOnReopen() {
        var editor = ProfileNutritionEditor()
        let selected = ProfileNutritionSettings(
            foodType: .vegan,
            isGlutenFree: true,
            isLactoseFree: true,
            hasDiabetes: true,
            allergens: [.milkProtein, .eggs, .sesame],
            dietTableName: "Стол № 5"
        )

        editor.open()
        editor.draft = selected
        XCTAssertEqual(editor.saved, ProfileNutritionSettings())

        editor.save()
        XCTAssertFalse(editor.isEditing)
        XCTAssertEqual(editor.saved, selected)

        editor.open()
        XCTAssertEqual(editor.draft, selected)
    }

    @MainActor
    func testCancelDiscardsDraftAndPreservesSavedValues() {
        var editor = ProfileNutritionEditor()
        editor.open()
        editor.draft.foodType = .vegetarian
        editor.draft.allergens = [.milkProtein, .fish]
        editor.save()
        let saved = editor.saved

        editor.open()
        editor.draft.foodType = .vegan
        editor.draft.isLactoseFree = true
        editor.draft.allergens = [.soy]
        editor.draft.dietTableName = "Стол № 5"
        editor.cancel()
        XCTAssertFalse(editor.isEditing)
        XCTAssertEqual(editor.saved, saved)

        editor.open()
        XCTAssertEqual(editor.draft, saved)
        XCTAssertTrue(editor.draft.allergens.contains(.milkProtein))
        XCTAssertFalse(editor.draft.isLactoseFree)
    }
}
