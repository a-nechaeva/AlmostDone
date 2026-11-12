import Foundation
import SwiftUI
import UIKit

struct RecipeScreen: View {
    @Environment(SessionStore.self) private var session: SessionStore?
    private let request: RecipeRequest

    init(recipeID: Recipe.ID) {
        self.init(recipeID: recipeID, servings: nil)
    }

    init(recipeID: Recipe.ID, servings: Int?, excludedAllergenIDs: [String] = []) {
        request = RecipeRequest(id: recipeID, servings: servings, excludedAllergenIDs: excludedAllergenIDs)
    }

    var body: some View {
        Group {
            if let session {
                if let account = session.account {
                    ServerRecipeScreen(
                        repository: RecipeRepository(session: session, account: account, request: request)
                    )
                    .id(ServerIdentity(accountID: account.id, request: request))
                } else {
                    ContentUnavailableView("Войдите, чтобы открыть рецепт", systemImage: "person.crop.circle")
                }
            } else {
                DemoRecipeScreen(recipeID: request.id)
                    .id(request.id)
            }
        }
        .background(Color(.demoBackground).ignoresSafeArea())
        .navigationTitle("Рецепт")
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct ServerIdentity: Hashable {
        let accountID: UUID
        let request: RecipeRequest
    }
}

private struct DemoRecipeScreen: View {
    @Environment(DemoStore.self) private var store
    let recipeID: Recipe.ID

    var body: some View {
        Group {
            if let recipe = store.recipe(id: recipeID) {
                let missingIDs = Set(store.missingIngredients(for: recipe).map(\.id))
                let image = RecipePresentation.demo[recipe.id].flatMap { UIImage(named: $0.photoName) }
                RecipeDetailsScreen(
                    presentation: RecipePresentation(demo: recipe, missingIDs: missingIDs),
                    photo: image.map(RecipePhoto.image) ?? .unavailable
                )
            } else {
                ContentUnavailableView("Рецепт не найден", systemImage: "fork.knife")
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("Демоданные")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ServerRecipeScreen: View {
    @State private var model: RecipeScreenModel

    init(repository: RecipeRepository) {
        _model = State(initialValue: RecipeScreenModel(repository: repository))
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView("Загружаем рецепт…")
            case .notFound:
                ContentUnavailableView("Рецепт не найден", systemImage: "fork.knife")
            case .failed(let retryAfter):
                ContentUnavailableView {
                    Label("Не удалось загрузить рецепт", systemImage: "exclamationmark.circle")
                } actions: {
                    RecipeRetryButton(retryAfter: retryAfter, retry: model.retry)
                }
            case .loaded(let presentation):
                RecipeDetailsScreen(
                    presentation: presentation, photo: model.photo, servingsModel: model,
                    ingredientNutrition: model.ingredientNutrition
                )
                .task(id: presentation.servings?.count) {
                    await model.loadIngredientNutrition()
                }
            }
        }
        .task(id: model.attempt) { [attempt = model.attempt] in
            await model.load(attempt: attempt)
        }
        .task(id: model.photoURL) { [url = model.photoURL] in
            await model.loadPhoto(for: url)
        }
    }
}

private struct RecipeRetryButton: View {
    let retryAfter: Date?
    let retry: () -> Void

    var body: some View {
        if let retryAfter {
            TimelineView(.explicit([.now, retryAfter])) { _ in
                button.disabled(Date.now < retryAfter)
            }
        } else {
            button
        }
    }

    private var button: some View {
        Button("Повторить", action: retry)
            .buttonStyle(.bordered)
    }
}

private struct RecipeServingsControl: View {
    let model: RecipeScreenModel
    let confirmedServings: RecipePresentation.Servings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let retryAfter = model.servingsUpdate?.retryAfter {
                TimelineView(.explicit([.now, retryAfter])) { _ in
                    buttons.disabled(Date.now < retryAfter)
                }
            } else {
                buttons
            }

            switch model.servingsUpdate {
            case .loading(let servings):
                let target = RecipePresentation.Servings(count: servings).accusativeDescription
                ProgressView("Рассчитываем на \(target)…")
                    .font(.caption)
            case .failed(let servings, let retryAfter):
                let target = RecipePresentation.Servings(count: servings).accusativeDescription
                Text("Не удалось пересчитать на \(target)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                RecipeRetryButton(retryAfter: retryAfter, retry: model.retry)
            case nil:
                EmptyView()
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            button(symbol: "minus", label: "Уменьшить число порций", delta: -1)
            Text(confirmedServings.description)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
            button(symbol: "plus", label: "Увеличить число порций", delta: 1)
        }
    }

    private func button(symbol: String, label: String, delta: Int) -> some View {
        let selectedServings = model.selectedServings ?? confirmedServings.count
        return Button {
            model.changeServings(by: delta)
        } label: {
            Image(systemName: symbol)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
        .disabled(!RecipeRequest.servingsRange.contains(selectedServings + delta))
    }
}

private struct RecipeDetailsScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsSteps = false
    let presentation: RecipePresentation
    let photo: RecipePhoto
    var servingsModel: RecipeScreenModel? = nil
    var ingredientNutrition: [String: IngredientNutrition] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                recipePhoto

                Text(presentation.title)
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                availability
                RecipeMetrics(presentation: presentation)
                    .padding(.top, 20)

                if let servingsModel, let servings = presentation.servings {
                    RecipeServingsControl(model: servingsModel, confirmedServings: servings)
                        .padding(.top, 20)
                }

                ingredients
                    .padding(.top, 28)

                if !presentation.purchases.isEmpty {
                    purchases
                        .padding(.top, 28)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
        .navigationDestination(isPresented: $showsSteps) {
            RecipeStepsScreen(title: presentation.title, servings: presentation.servings, steps: presentation.steps)
        }
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ингредиенты")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)

            if let servings = presentation.servings {
                Text(servings.ingredientCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                ForEach(presentation.ingredients) { ingredient in
                    RecipeIngredientRow(
                        ingredient: ingredient, nutrition: ingredientNutrition[ingredient.id], readyColor: readyColor
                    )
                }
            }
            .padding(.top, 8)
        }
    }

    private var purchases: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Упаковки к покупке")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)

            ForEach(presentation.purchases) { purchase in
                VStack(alignment: .leading, spacing: 4) {
                    Text(purchase.name)
                        .font(.subheadline.weight(.medium))
                    Text("\(purchase.packages) · \(purchase.price)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var recipePhoto: some View {
        Color.primary.opacity(0.05)
            .aspectRatio(372.0 / 206.0, contentMode: .fit)
            .overlay {
                switch photo {
                case .image(let image):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .accessibilityHidden(true)
                case .loading:
                    ProgressView().accessibilityLabel("Загружаем фото")
                case .unavailable:
                    Label("Фото недоступно", systemImage: "photo")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .clipShape(.rect(cornerRadius: 24))
    }

    private var availability: some View {
        let tint: Color =
            switch presentation.availability {
            case .ready: readyColor
            case .missing: .accentColor
            case .unknown: .secondary
            }

        return Label {
            Text(presentation.availability.label)
        } icon: {
            Image(systemName: presentation.availability.icon)
                .accessibilityHidden(true)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 10))
    }

    private var footer: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))

        return layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.costCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(presentation.cost)
                    .font(.title3.bold())
            }
            .frame(minWidth: 92, alignment: .leading)
            .accessibilityElement(children: .combine)

            if !presentation.steps.isEmpty {
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
