import SwiftUI
import UIKit

struct RecipeScreen: View {
    @Environment(DemoStore.self) private var store
    @AccessibilityFocusState(for: .voiceOver) private var isStepsHeadingFocused: Bool
    let recipeID: Recipe.ID

    var body: some View {
        Group {
            if let recipe = store.recipe(id: recipeID) {
                recipeDetails(recipe, presentation: RecipePresentation.demo[recipe.id])
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

    private func recipeDetails(_ recipe: Recipe, presentation: RecipePresentation?) -> some View {
        let missingIDs = Set(store.missingIngredients(for: recipe).map(\.id))

        return ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    photo(named: presentation?.photoName)

                    VStack(alignment: .leading, spacing: 14) {
                        Text(recipe.title)
                            .font(.title.bold())
                            .accessibilityAddTraits(.isHeader)

                        availability(isReady: missingIDs.isEmpty)
                        metrics(presentation)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                sectionTitle("Ингредиенты")
                                Spacer()
                                stepsButton(scroll)
                            }
                            VStack(alignment: .leading) {
                                sectionTitle("Ингредиенты")
                                stepsButton(scroll)
                            }
                        }

                        ForEach(recipe.ingredients) { ingredient in
                            ingredientRow(ingredient, isAtHome: !missingIDs.contains(ingredient.id))
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Как приготовить")
                            .accessibilityFocused($isStepsHeadingFocused)

                        ForEach(recipe.steps.indices, id: \.self) { index in
                            stepCard(number: index + 1, text: recipe.steps[index])
                        }
                    }
                    .id(Section.steps)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
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

    private func availability(isReady: Bool) -> some View {
        let tint: Color = isReady ? .green : .accentColor

        return Label(
            isReady ? "Все продукты есть" : "Нужно докупить",
            systemImage: isReady ? "checkmark" : "bag"
        )
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 10))
    }

    @ViewBuilder
    private func metrics(_ presentation: RecipePresentation?) -> some View {
        if let presentation {
            metric("\(presentation.minutes) мин", caption: "время приготовления", icon: "clock")

            if let nutrition = presentation.nutrition {
                metric("\(nutrition.kilocalories) ккал", caption: "на порцию", icon: "flame")
                Text("На порцию — Б \(nutrition.protein) · Ж \(nutrition.fat) · У \(nutrition.carbohydrates) г")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !presentation.allergens.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Аллергены")
                        .font(.subheadline.bold())
                        .accessibilityAddTraits(.isHeader)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            allergenChips(presentation.allergens)
                        }
                        .fixedSize(horizontal: true, vertical: false)

                        VStack(alignment: .leading, spacing: 8) {
                            allergenChips(presentation.allergens)
                        }
                    }
                }
            }
        }
    }

    private func metric(_ value: String, caption: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(value).font(.headline)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 20))
    }

    private func allergenChips(_ allergens: [String]) -> some View {
        ForEach(allergens, id: \.self) { allergen in
            Text(allergen)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(uiColor: .systemBackground), in: .capsule)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .accessibilityAddTraits(.isHeader)
    }

    private func stepsButton(_ scroll: ScrollViewProxy) -> some View {
        Button {
            scroll.scrollTo(Section.steps, anchor: .top)
            isStepsHeadingFocused = true
        } label: {
            Label("К шагам", systemImage: "arrow.down")
                .font(.subheadline.weight(.medium))
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderless)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityIdentifier("recipe.steps")
    }

    private func ingredientRow(_ ingredient: Ingredient, isAtHome: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isAtHome ? "checkmark" : "bag")
                .foregroundStyle(isAtHome ? Color.green : Color.accentColor)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(ingredient.name)
                    .font(.subheadline.weight(.medium))
                Text(isAtHome ? "Есть дома" : "Нужно докупить")
                    .font(.footnote)
                    .foregroundStyle(isAtHome ? Color.secondary : Color.accentColor)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recipe.ingredient.\(ingredient.id)")
    }

    private func stepCard(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.bold())
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12), in: .capsule)

            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    private enum Section {
        case steps
    }
}
