import SwiftUI

struct RecipeScreen: View {
    @Environment(DemoStore.self) private var store
    let recipeID: Recipe.ID

    var body: some View {
        Group {
            if let recipe = store.recipe(id: recipeID) {
                recipeDetails(recipe)
            } else {
                ContentUnavailableView("Рецепт не найден", systemImage: "fork.knife")
            }
        }
        .background(Color(.demoBackground))
        .navigationTitle("Рецепт")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("Демоданные")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func recipeDetails(_ recipe: Recipe) -> some View {
        List {
            Text(recipe.title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Section("Ингредиенты") {
                ForEach(recipe.ingredients) { ingredient in
                    let isAtHome = store.productIDs.contains(ingredient.id)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ingredient.name)
                        Text(isAtHome ? "Есть дома" : "Нужно докупить")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Как приготовить") {
                ForEach(recipe.steps.indices, id: \.self) { index in
                    Text("\(index + 1). \(recipe.steps[index])")
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}
