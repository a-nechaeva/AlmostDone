import SwiftUI

struct DishesScreen: View {
    @Environment(DemoStore.self) private var store

    var body: some View {
        let recipesByAvailability = Dictionary(grouping: store.recipes) { recipe in
            store.missingIngredients(for: recipe).isEmpty
        }

        List {
            if let ready = recipesByAvailability[true] {
                Section("Можно сейчас") {
                    ForEach(ready) { recipe in
                        dishLink(recipe, subtitle: "Все продукты есть")
                    }
                }
            }

            if let needsShopping = recipesByAvailability[false] {
                Section("Нужно докупить") {
                    ForEach(needsShopping) { recipe in
                        let names = store.missingIngredients(for: recipe).map(\.name)
                        dishLink(recipe, subtitle: names.joined(separator: ", "))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.demoBackground))
        .navigationTitle("Блюда")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("Демоданные")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dishLink(_ recipe: Recipe, subtitle: String) -> some View {
        NavigationLink(value: Route.recipe(recipe.id)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}
