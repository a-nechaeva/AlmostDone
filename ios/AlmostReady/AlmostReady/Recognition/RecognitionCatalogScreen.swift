import SwiftUI

struct RecognitionCatalogScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: IngredientSearchModel
    let onSelect: (CatalogIngredient) -> Void

    init(repository: ProductsRepository, onSelect: @escaping (CatalogIngredient) -> Void) {
        _model = State(initialValue: IngredientSearchModel(repository: repository))
        self.onSelect = onSelect
    }

    var body: some View {
        @Bindable var model = model
        let requestID = model.requestID
        NavigationStack {
            List {
                TextField("Название продукта", text: $model.query)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityIdentifier("products.photo.catalog.search")
                switch model.phase {
                case .idle:
                    Text("Введите название продукта")
                case .loading:
                    ProgressView("Ищем продукты")
                case .failed:
                    Text("Не удалось загрузить каталог")
                    Button("Повторить", action: model.restart)
                case .results(let ingredients):
                    if ingredients.isEmpty { Text("Продукты не найдены") }
                    ForEach(ingredients) { ingredient in
                        Button(ingredient.name) { onSelect(ingredient) }
                    }
                    if model.isLoadingMore {
                        ProgressView("Ищем продукты")
                    } else if model.pageLoadFailed || model.nextCursor != nil {
                        Button(model.pageLoadFailed ? "Повторить" : "Показать ещё") {
                            Task { await model.loadMore() }
                        }
                    }
                }
            }
            .navigationTitle("Каталог продуктов")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .task(id: requestID) {
            guard (try? await Task.sleep(for: .milliseconds(250))) != nil else { return }
            await model.search(request: requestID)
        }
    }
}
