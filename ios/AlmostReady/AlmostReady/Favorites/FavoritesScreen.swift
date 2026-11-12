import SwiftUI

struct FavoritesScreen: View {
    @State private var category = FavoritesCategory.recipes
    @State private var selectedRecipeID: String?
    @State private var isEditorPresented = false
    @State private var pantryRequest: FavoriteEntry?
    @State private var failedPantryEntry: FavoriteEntry?
    let favorites: FavoritesStore

    var body: some View {
        let state = favorites.state(for: category)
        List {
            Picker("Категория избранного", selection: $category) {
                Text("Блюда").tag(FavoritesCategory.recipes)
                Text("Ингредиенты").tag(FavoritesCategory.ingredients)
            }
            .pickerStyle(.segmented)
            .disabled(pantryRequest != nil)
            .accessibilityIdentifier("favorites.category")

            if category == .ingredients {
                pantryFeedback
            }

            ForEach(state.failedChanges.values.sorted { $0.entry.id < $1.entry.id }, id: \.entry.id) { change in
                let selected = category
                Text("Не удалось изменить избранное: \(change.entry.name)")
                TimelineView(retrySchedule(state.retryAfter)) { context in
                    Button("Повторить") { Task { await favorites.set(change, in: selected) } }
                        .buttonStyle(.borderless)
                        .disabled(state.isLoading || state.isSaving || !state.canRequest(at: context.date))
                    Button("Закрыть сообщение") { favorites.dismissFailedChange(for: change.entry.id, in: selected) }
                        .buttonStyle(.borderless)
                        .disabled(state.isSaving)
                }
            }
            if state.isLoading || state.isSaving {
                ProgressView(state.isSaving ? "Обновляем избранное…" : "Загружаем избранное…")
            } else if state.loadFailed {
                let selected = category
                Text("Не удалось загрузить избранное")
                TimelineView(retrySchedule(state.retryAfter)) { context in
                    Button("Повторить") { Task { await favorites.load(selected, force: true) } }
                        .disabled(!state.canRequest(at: context.date))
                }
            }

            if let snapshot = state.snapshot {
                if snapshot.entries.isEmpty, !state.isLoading, !state.loadFailed {
                    Text(category == .recipes ? "Нет избранных блюд" : "Нет избранных ингредиентов")
                        .foregroundStyle(.secondary)
                }
                ForEach(snapshot.entries) { entry in
                    row(entry, state: state, category: category)
                }
            }
        }
        .navigationTitle("Избранное")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationDestination(isPresented: recipePresentation) {
            if let selectedRecipeID {
                RecipeScreen(recipeID: selectedRecipeID)
                    .toolbar(.visible, for: .navigationBar)
            }
        }
        .task(id: category) { await favorites.load(category) }
        .task(id: pantryRequest) { [pantryRequest] in
            if let pantryRequest { await preparePantry(for: pantryRequest) }
        }
        .refreshable { await favorites.load(category, force: true) }
        .sheet(isPresented: $isEditorPresented) {
            if let draft = favorites.pantryDraft {
                PantryEditor(draft: draft, model: favorites.pantry) {
                    isEditorPresented = false
                }
            }
        }
        .onChange(of: isEditorPresented) { _, isPresented in
            if !isPresented { favorites.dismissPantryDraft() }
        }
    }

    @ViewBuilder
    private var pantryFeedback: some View {
        if pantryRequest != nil {
            ProgressView("Загружаем запасы…")
        } else if let entry = failedPantryEntry {
            Text("Не удалось подготовить добавление в запасы")
            Button("Повторить") { pantryRequest = entry }
        }
        if favorites.pantryDraft?.hasPendingAdd == true {
            Button("Продолжить добавление") { isEditorPresented = true }
        }
    }

    private func row(_ entry: FavoriteEntry, state: FavoritesStore.State, category: FavoritesCategory) -> some View {
        HStack {
            if category == .recipes {
                Button {
                    selectedRecipeID = entry.id
                } label: {
                    HStack {
                        Text(entry.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("favorites.recipe.\(entry.id)")
            } else {
                Text(entry.name)
                Spacer()
                Button {
                    pantryRequest = entry
                } label: {
                    Image(systemName: "plus.circle")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Добавить в запасы: \(entry.name)")
                .accessibilityIdentifier("favorites.pantry.\(entry.id)")
                .disabled(pantryRequest != nil || favorites.pantryDraft?.hasPendingAdd == true)
            }
            if let deadline = state.retryAfter, !state.canRequest() {
                TimelineView(retrySchedule(deadline)) { context in
                    removeButton(entry, state: state, category: category)
                        .disabled(!state.canRequest(at: context.date))
                }
            } else {
                removeButton(entry, state: state, category: category)
            }
        }
    }

    private func removeButton(
        _ entry: FavoriteEntry, state: FavoritesStore.State, category: FavoritesCategory
    ) -> some View {
        Button(role: .destructive) {
            Task { await favorites.set(.init(entry: entry, isFavorite: false), in: category) }
        } label: {
            Image(systemName: "heart.slash")
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Удалить из избранного: \(entry.name)")
        .accessibilityIdentifier("favorites.remove.\(category.rawValue).\(entry.id)")
        .disabled(state.isLoading || state.isSaving || state.loadFailed || state.failedChanges[entry.id] != nil)
    }

    private var recipePresentation: Binding<Bool> {
        // The recipe stays open if its favorite row disappears after a confirmed removal.
        Binding(
            get: { selectedRecipeID != nil },
            set: { if !$0 { selectedRecipeID = nil } }
        )
    }

    private func retrySchedule(_ deadline: Date?) -> ExplicitTimelineSchedule<[Date]> {
        .explicit([.now] + (deadline.map { [$0] } ?? []).filter { $0 > .now })
    }

    private func preparePantry(for entry: FavoriteEntry) async {
        failedPantryEntry = nil
        let prepared = await favorites.preparePantryDraft(for: entry)
        guard !Task.isCancelled, favorites.repository.isCurrent else { return }
        pantryRequest = nil
        if prepared {
            isEditorPresented = true
        } else {
            failedPantryEntry = entry
        }
    }
}
