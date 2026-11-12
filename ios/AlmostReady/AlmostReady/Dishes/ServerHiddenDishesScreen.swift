import SwiftUI

struct ServerHiddenDishesScreen: View {
    @State private var model: ServerDishesModel

    init(repository: RecommendationsRepository, route: HiddenDishesRoute) {
        _model = State(
            initialValue: ServerDishesModel(repository: repository, initialContext: route.context, visibility: .hidden)
        )
    }

    var body: some View {
        let context = model.context

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                switch model.phase {
                case .loading:
                    ProgressView("Загружаем скрытые блюда…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                case .failed:
                    ContentUnavailableView {
                        Label("Не удалось загрузить скрытые блюда", systemImage: "exclamationmark.circle")
                    } actions: {
                        Button("Повторить") { Task { await model.retry() } }
                    }
                case .loaded(let snapshot):
                    if snapshot.items.isEmpty {
                        ContentUnavailableView("Скрытых блюд нет", systemImage: "eye")
                    } else {
                        ForEach(snapshot.items) { card in
                            NavigationLink(value: snapshot.recipeRequest(for: card)) {
                                ServerDishCard(card: card, repository: model.repository)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("dishes.hidden.recipe.\(card.id)")
                        }
                    }
                    DishesNextPage(snapshot: snapshot, model: model)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color(.demoBackground).ignoresSafeArea())
        .navigationTitle("Скрытые блюда")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: context) { await model.loadIfNeeded(for: context) }
    }
}

struct DishesNextPage: View {
    let snapshot: DishesSnapshot
    let model: ServerDishesModel

    var body: some View {
        if snapshot.nextCursor != nil {
            VStack(spacing: 8) {
                if model.pageLoadFailed {
                    Text("Не удалось загрузить следующую страницу")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if model.isLoadingMore {
                    ProgressView("Загружаем блюда…")
                } else {
                    Button(model.pageLoadFailed ? "Повторить" : "Показать ещё") {
                        Task { await model.loadMore() }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
