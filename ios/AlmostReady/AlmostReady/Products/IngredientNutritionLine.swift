import Foundation
import SwiftUI

struct IngredientNutritionLine: View {
    let nutrition: IngredientNutrition?

    var body: some View {
        if let label {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var label: String? {
        guard let nutrition else { return nil }
        let format = Decimal.FormatStyle.number.locale(Locale(identifier: "ru_RU"))
        let kcal = nutrition.kcal.formatted(format)
        let protein = nutrition.protein.formatted(format)
        let fat = nutrition.fat.formatted(format)
        let carbs = nutrition.carbs.formatted(format)
        return "КБЖУ на 100 г · \(kcal) ккал · Б \(protein) г · Ж \(fat) г · У \(carbs) г"
    }
}
