import SwiftUI

struct RecipeIngredientRow: View {
    let ingredient: RecipePresentation.IngredientRow
    let nutrition: IngredientNutrition?
    let readyColor: Color

    var body: some View {
        let (icon, tint): (String, Color) =
            switch ingredient.availability {
            case .enough: ("checkmark", readyColor)
            case .missing: ("plus", .accentColor)
            case .unknown: ("questionmark", .secondary)
            case .optional: ("circle", .secondary)
            }

        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(ingredient.name)
                    .font(.subheadline.weight(.medium))
                Text(ingredient.status)
                    .font(.caption)
                    .foregroundStyle(ingredient.availability == .missing ? Color.accentColor : Color.secondary)
                if let note = ingredient.originalAmountNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                IngredientNutritionLine(nutrition: nutrition)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            if let amount = ingredient.amount {
                Text(amount)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 94, alignment: .trailing)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recipe.ingredient.\(ingredient.id)")
    }
}
