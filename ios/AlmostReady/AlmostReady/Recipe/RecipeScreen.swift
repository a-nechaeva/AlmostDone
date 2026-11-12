import SwiftUI
import UIKit

struct RecipeScreen: View {
    @Environment(DemoStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsSteps = false
    let recipeID: Recipe.ID

    var body: some View {
        Group {
            if let recipe = store.recipe(id: recipeID) {
                let presentation = RecipePresentation.demo[recipe.id]
                recipeDetails(recipe, presentation: presentation)
                    .navigationDestination(isPresented: $showsSteps) {
                        RecipeStepsScreen(recipe: recipe, servings: presentation?.servings)
                    }
            } else {
                ContentUnavailableView("Рецепт не найден", systemImage: "fork.knife")
            }
        }
        .background(Color(.demoBackground).ignoresSafeArea())
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

    private func recipeDetails(_ recipe: Recipe, presentation: RecipePresentation?) -> some View {
        let missingIDs = Set(store.missingIngredients(for: recipe).map(\.id))

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                photo(named: presentation?.photoName)

                Text(recipe.title)
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                availability(missingCount: missingIDs.count)
                if let presentation {
                    RecipeMetrics(presentation: presentation)
                        .padding(.top, 20)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ингредиенты")
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)

                    if let servings = presentation?.servings {
                        Text(servings.ingredientCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 4) {
                        ForEach(recipe.ingredients) { ingredient in
                            ingredientRow(
                                ingredient,
                                isAtHome: !missingIDs.contains(ingredient.id),
                                amount: presentation?.ingredientAmounts[ingredient.id]
                            )
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer(missingIDs: missingIDs, hasSteps: !recipe.steps.isEmpty)
        }
    }

    private func photo(named name: String?) -> some View {
        Color.primary.opacity(0.05)
            .aspectRatio(372.0 / 206.0, contentMode: .fit)
            .overlay {
                if let name, let image = UIImage(named: name) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .accessibilityHidden(true)
                } else {
                    Label("Фото недоступно", systemImage: "photo")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .clipShape(.rect(cornerRadius: 24))
    }

    private func availability(missingCount: Int) -> some View {
        let isReady = missingCount == 0
        let tint = isReady ? readyColor : .accentColor

        return Label {
            if isReady {
                Text("Все продукты есть")
            } else {
                Text(RecipePresentation.shoppingBadge(missingCount: missingCount))
            }
        } icon: {
            Image(systemName: isReady ? "checkmark" : "bag")
                .accessibilityHidden(true)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 10))
    }

    private func ingredientRow(_ ingredient: Ingredient, isAtHome: Bool, amount: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isAtHome ? "checkmark" : "plus")
                .foregroundStyle(isAtHome ? readyColor : Color.accentColor)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(ingredient.name)
                    .font(.subheadline.weight(.medium))
                Text(isAtHome ? "Есть дома" : "Нужно докупить")
                    .font(.caption)
                    .foregroundStyle(isAtHome ? Color.secondary : Color.accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            if let amount {
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

    private func footer(missingIDs: Set<Ingredient.ID>, hasSteps: Bool) -> some View {
        let price = RecipePresentation.packagePrice(for: missingIDs)
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))

        return layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(price == nil ? "Докупка" : "За упаковку")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(price ?? (missingIDs.isEmpty ? "Не нужна" : "Нужна"))
                    .font(.title3.bold())
            }
            .frame(minWidth: 92, alignment: .leading)
            .accessibilityElement(children: .combine)

            if hasSteps {
                Button("К приготовлению") {
                    showsSteps = true
                }
                .buttonStyle(RecipeStepsButtonStyle())
                .accessibilityIdentifier("recipe.steps")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(.demoBackground))
    }

    private var readyColor: Color {
        colorScheme == .dark ? Color(red: 0.60, green: 0.82, blue: 0.68) : Color(red: 0.20, green: 0.41, blue: 0.29)
    }
}

private struct RecipeStepsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.accentColor.opacity(0.14), in: .rect(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
