import SwiftUI

struct ServerProductsTab: View {
    @Environment(FavoritesStore.self) private var favorites: FavoritesStore?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.floatingTabBarHeight) private var tabBarHeight
    @Binding var isSearchPresented: Bool
    @State private var model: PantryModel
    @State private var draft: PantryDraft?
    @State private var isEditorPresented = false
    @State private var photoImport: PhotoImportModel?
    @State private var photoImportPresentation: PhotoImportModel?
    let onOpenDishes: () -> Void

    init(repository: ProductsRepository, isSearchPresented: Binding<Bool>, onOpenDishes: @escaping () -> Void) {
        _model = State(initialValue: PantryModel(repository: repository))
        _isSearchPresented = isSearchPresented
        self.onOpenDishes = onOpenDishes
    }

    var body: some View {
        let editorDraft = draft
        NavigationStack {
            List {
                RootScreenTitle(tab: .products)
                if let snapshot = model.snapshot {
                    Button("Добавить продукт", systemImage: "magnifyingglass") {
                        isSearchPresented = true
                    }
                    .accessibilityIdentifier("products.search.open")
                    Button("Добавить по фото", systemImage: "camera") {
                        if photoImport?.hasPendingImport != true {
                            photoImport = PhotoImportModel(pantry: model)
                        }
                        photoImportPresentation = photoImport
                    }
                    .accessibilityIdentifier("products.photo.open")
                    if snapshot.items.isEmpty {
                        Text("Список пуст. Найдите продукт, чтобы добавить его")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(snapshot.items) { item in
                        HStack {
                            Button {
                                openEditor(.edit(item), snapshot: snapshot)
                            } label: {
                                PantryItemLabel(item: item, model: model)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("products.home.\(item.id)")
                            FavoriteButton(category: .ingredients, entry: FavoriteEntry(id: item.id, name: item.name))
                        }
                    }
                }
                if model.isLoading {
                    ProgressView("Загружаем продукты")
                } else if model.loadFailed {
                    Text(model.snapshot == nil ? "Не удалось загрузить запасы" : "Не удалось обновить запасы")
                    Button("Повторить") { Task { await model.reload() } }
                }
                if hasPendingAdd {
                    Button("Продолжить добавление", action: resumeAdd)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                dishesButton
            }
            .refreshable { await model.reload() }
            .task { await model.reloadIfNeeded() }
            .task { await favorites?.load(.ingredients) }
            .navigationDestination(isPresented: $isSearchPresented) {
                ServerProductsSearchScreen(
                    repository: model.repository, hasPendingAdd: hasPendingAdd, onResumeAdd: resumeAdd
                ) { ingredient in
                    guard let snapshot = model.snapshot else { return }
                    openEditor(.add(ingredient), snapshot: snapshot)
                }
            }
        }
        .fullScreenCover(
            item: $photoImportPresentation,
            onDismiss: {
                if photoImport?.hasPendingImport != true { photoImport = nil }
            }
        ) { photoImport in
            PhotoImportScreen(model: photoImport)
        }
        .sheet(isPresented: $isEditorPresented) {
            if let editorDraft {
                PantryEditor(draft: editorDraft, model: model) {
                    isEditorPresented = false
                }
            }
        }
    }

    private var dishesButton: some View {
        Button(action: onOpenDishes) {
            Text("Подобрать блюда")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(ProductsPalette(colorScheme: colorScheme).action, in: .rect(cornerRadius: 16))
                .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("products.dishes")
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, tabBarHeight + 20)
    }

    private var hasPendingAdd: Bool { draft?.hasPendingAdd == true }

    private func openEditor(_ kind: PantryDraft.Kind, snapshot: PantrySnapshot) {
        guard !hasPendingAdd else {
            resumeAdd()
            return
        }
        draft = PantryDraft(kind: kind, snapshot: snapshot)
        isEditorPresented = true
    }

    private func resumeAdd() {
        isEditorPresented = true
    }
}

private struct ServerProductsSearchScreen: View {
    @Environment(FavoritesStore.self) private var favorites: FavoritesStore?
    @State private var model: IngredientSearchModel
    @FocusState private var searchFocused: Bool
    let hasPendingAdd: Bool
    let onResumeAdd: () -> Void
    let onSelect: (CatalogIngredient) -> Void

    init(
        repository: ProductsRepository, hasPendingAdd: Bool,
        onResumeAdd: @escaping () -> Void, onSelect: @escaping (CatalogIngredient) -> Void
    ) {
        _model = State(initialValue: IngredientSearchModel(repository: repository))
        self.hasPendingAdd = hasPendingAdd
        self.onResumeAdd = onResumeAdd
        self.onSelect = onSelect
    }

    var body: some View {
        @Bindable var model = model
        let requestID = model.requestID
        List {
            TextField("Название продукта", text: $model.query)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .accessibilityIdentifier("products.search")
            if hasPendingAdd {
                Button("Продолжить добавление", action: onResumeAdd)
            }
            switch model.phase {
            case .idle:
                Text("Введите название, чтобы найти продукт")
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView("Ищем продукты")
            case .results(let ingredients) where ingredients.isEmpty:
                Text("Продукты не найдены")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("products.search.empty")
            case .results(let ingredients):
                ForEach(ingredients) { ingredient in
                    HStack {
                        Button {
                            searchFocused = false
                            onSelect(ingredient)
                        } label: {
                            IngredientSuggestionLabel(ingredient: ingredient)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .disabled(hasPendingAdd)
                        .accessibilityIdentifier("products.add.\(ingredient.id)")
                        FavoriteButton(
                            category: .ingredients,
                            entry: FavoriteEntry(
                                id: ingredient.id, name: ingredient.name, allowedUnits: ingredient.allowedUnits
                            )
                        )
                    }
                }
                if model.isLoadingMore {
                    ProgressView("Ищем продукты")
                } else if model.pageLoadFailed {
                    Text("Не удалось загрузить следующие подсказки")
                    Button("Повторить") { Task { await model.loadMore() } }
                } else if model.nextCursor != nil {
                    Button("Показать ещё") { Task { await model.loadMore() } }
                }
            case .failed:
                Text("Не удалось загрузить подсказки")
                Button("Повторить", action: model.restart)
            }
        }
        .navigationTitle("Добавить продукт")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .defaultFocus($searchFocused, true)
        .task { await favorites?.load(.ingredients) }
        .task(id: requestID) {
            // Avoid sending a request for every keystroke.
            guard (try? await Task.sleep(for: .milliseconds(250))) != nil else { return }
            await model.search(request: requestID)
        }
    }
}

extension PantryUnit {
    var label: String {
        switch self {
        case .grams: "г"
        case .milliliters: "мл"
        case .pieces: "шт."
        }
    }
}

extension PantryQuantity {
    var label: String {
        "\(value.formatted()) \(unit.label)"
    }
}
