import SwiftUI

struct PantryItemLabel: View {
    let item: PantryItem
    let model: PantryModel

    var body: some View {
        VStack(alignment: .leading) {
            Text(item.name)
                .foregroundStyle(.primary)
            Text(item.quantity?.label ?? "Количество не указано")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            IngredientNutritionLine(nutrition: model.nutrition(for: item))
        }
    }
}

struct IngredientSuggestionLabel: View {
    let ingredient: CatalogIngredient

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(ingredient.name)
                IngredientNutritionLine(nutrition: ingredient.nutrition)
            }
        } icon: {
            Image(systemName: "plus")
        }
    }
}
