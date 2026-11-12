import SwiftUI

struct ServerDishesScreen: View {
    @Environment(\.floatingTabBarHeight) private var tabBarHeight
    @ScaledMetric(relativeTo: .headline) private var sectionTitleSize = 18.0
    @State private var model: ServerDishesModel
    @FocusState.Binding var isSearchFocused: Bool

    let onOpenProducts: () -> Void

    init(
        repository: RecommendationsRepository, isSearchFocused: FocusState<Bool>.Binding,
        onOpenProducts: @escaping () -> Void
    ) {
        _model = State(initialValue: ServerDishesModel(repository: repository))
        _isSearchFocused = isSearchFocused
        self.onOpenProducts = onOpenProducts
    }

    var body: some View {
        @Bindable var model = model
        let context = model.context

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    RootScreenTitle(tab: .dishes)
                    Button("Изменить продукты дома", action: onOpenProducts)
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 44)
                }

                DishesControls(query: $model.query, filter: $model.filter, isSearchFocused: $isSearchFocused)
                switch model.phase {
                case .loading:
                    ProgressView("Подбираем блюда…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                case .failed:
                    ContentUnavailableView {
                        Label("Не удалось подобрать блюда", systemImage: "exclamationmark.circle")
                    } actions: {
                        Button("Повторить") { Task { await model.retry() } }
                    }
                case .loaded(let snapshot):
                    results(snapshot)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .safeAreaPadding(.bottom, tabBarHeight)
        .toolbar(.hidden, for: .navigationBar)
        .background(Color(.demoBackground).ignoresSafeArea())
        .onDisappear { isSearchFocused = false }
        .task(id: context) {
            if !context.query.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
            }
            await model.loadIfNeeded(for: context)
        }
    }

    @ViewBuilder
    private func results(_ snapshot: DishesSnapshot) -> some View {
        let first = snapshot.firstPage
        VStack(alignment: .leading, spacing: 4) {
            Text("Найдено блюд — \(first.visibleTotal.formatted())")
            Text("Скрыто — \(first.hiddenTotal.formatted())")
            Text("Пригодность неизвестна — \(first.unknownTotal.formatted())")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)

        if snapshot.items.isEmpty {
            ContentUnavailableView {
                Label("Блюда не найдены", systemImage: "magnifyingglass")
            } actions: {
                if model.filter != .all || !model.query.isEmpty {
                    Button("Показать все блюда") {
                        model.query = ""
                        model.filter = .all
                        isSearchFocused = false
                    }
                }
            }
        } else {
            let groups = snapshot.groups
            ForEach(groups.keys.sorted(), id: \.self) { group in
                Section {
                    ForEach(groups[group, default: []]) { card in
                        let route = snapshot.recipeRequest(for: card)
                        VStack(alignment: .leading, spacing: 4) {
                            NavigationLink(value: route) {
                                ServerDishCard(card: card, repository: model.repository)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("dishes.recipe.\(card.id)")

                            if card.availability.missingCount > 0 {
                                ServerMissingProducts(
                                    repository: model.repository, route: route,
                                    snapshot: snapshot.firstPage, missingCount: card.availability.missingCount
                                ) {
                                    Task { await model.refreshSnapshot(requestID: first.requestID) }
                                }
                                .id(first.requestID)
                            }
                        }
                    }
                } header: {
                    Text(group.title)
                        .font(.system(size: sectionTitleSize, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }

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

extension DishesSnapshot.Group {
    fileprivate var title: String {
        switch self {
        case .ready: "Можно сейчас"
        case .missing(let count): "Докупить \(dishesProductCount(count))"
        case .unknown: "Наличие продуктов неизвестно"
        }
    }
}
