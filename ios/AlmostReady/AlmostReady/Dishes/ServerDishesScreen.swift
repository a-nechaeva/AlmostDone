import SwiftUI

struct HiddenDishesRoute: Hashable {
    let context: ServerDishesModel.Context
}

struct ServerDishesScreen: View {
    @Environment(ServerShoppingModel.self) private var shopping: ServerShoppingModel?
    @Environment(\.locale) private var locale
    @Environment(\.floatingTabBarHeight) private var tabBarHeight
    @ScaledMetric(relativeTo: .headline) private var sectionTitleSize = 18.0
    @State private var model: ServerDishesModel
    @State private var showsAdvancedFilters = false
    @FocusState.Binding var isSearchFocused: Bool

    let onOpenProducts: () -> Void
    let onOpenRecipe: (RecipeRequest) -> Void

    init(
        repository: RecommendationsRepository, isSearchFocused: FocusState<Bool>.Binding,
        onOpenProducts: @escaping () -> Void, onOpenRecipe: @escaping (RecipeRequest) -> Void
    ) {
        _model = State(initialValue: ServerDishesModel(repository: repository))
        _isSearchFocused = isSearchFocused
        self.onOpenProducts = onOpenProducts
        self.onOpenRecipe = onOpenRecipe
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
                Button {
                    isSearchFocused = false
                    showsAdvancedFilters = true
                } label: {
                    Label(
                        model.advancedFilters == DishesAdvancedFilters() ? "Фильтры" : "Фильтры применены",
                        systemImage: "slider.horizontal.3"
                    )
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("dishes.filters")
                Picker("Режим подбора", selection: $model.resultsMode) {
                    ForEach(ServerDishesModel.ResultsMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("dishes.resultsMode")
                .onChange(of: model.resultsMode) { isSearchFocused = false }

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
                    summary(snapshot)
                    if model.resultsMode == .graph, let graphSnapshot = model.graphSnapshot {
                        graph(graphSnapshot)
                    } else {
                        results(snapshot)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .safeAreaPadding(.bottom, tabBarHeight)
        .toolbar(.hidden, for: .navigationBar)
        .background(Color(.demoBackground).ignoresSafeArea())
        .navigationDestination(for: HiddenDishesRoute.self) { route in
            ServerHiddenDishesScreen(repository: model.repository, route: route)
        }
        .sheet(isPresented: $showsAdvancedFilters) {
            ServerDishesFiltersSheet(repository: model.repository, applied: model.advancedFilters, locale: locale) {
                model.apply($0)
            }
        }
        .onDisappear { isSearchFocused = false }
        .task(id: context) {
            if !context.query.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
            }
            await model.loadIfNeeded(for: context)
        }
    }

    @ViewBuilder
    private func summary(_ snapshot: DishesSnapshot) -> some View {
        let first = snapshot.firstPage
        VStack(alignment: .leading, spacing: 4) {
            Text("Найдено блюд — \(first.visibleTotal.formatted())")
            Text("Пригодность неизвестна — \(first.unknownTotal.formatted())")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)

        if first.hiddenTotal > 0 {
            NavigationLink(value: HiddenDishesRoute(context: snapshot.context)) {
                Label("Скрыто — \(first.hiddenTotal.formatted())", systemImage: "eye.slash")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("dishes.hidden")
        } else {
            Text("Скрыто — 0")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private struct GraphLoad: Equatable {
        let snapshot: RecommendationGraphSnapshot
        let retryAttempt: Int
    }

    private func graph(_ snapshot: RecommendationGraphSnapshot) -> some View {
        let phase = model.graph.phase(for: snapshot)
        let load = GraphLoad(snapshot: snapshot, retryAttempt: model.graph.retryAttempt)
        return RecommendationGraphView(
            phase: phase,
            onRetry: {
                guard model.graphSnapshot == snapshot else { return }
                model.graph.requestRetry(for: snapshot)
            },
            onRefreshSnapshot: { refreshGraph(snapshot) },
            onOpenRecipe: { request in
                guard model.graphSnapshot == snapshot, case .loaded = model.graph.phase(for: snapshot) else { return }
                onOpenRecipe(request)
            },
            shoppingState: { items, revision in
                shopping?.addition(for: items, basedOn: revision)
            },
            onAddSet: { items, revision in
                guard model.graphSnapshot == snapshot, case .loaded = model.graph.phase(for: snapshot) else {
                    return true
                }
                let result = shopping?.add(items, basedOn: revision)
                if result == .needsFreshSnapshot { refreshGraph(snapshot) }
                return result != .storageUnavailable
            },
            shoppingUnavailable: shopping?.storageUnavailable == true
        )
        .id(snapshot.requestID)
        .task(id: load) { await model.graph.loadIfNeeded(for: load.snapshot, retryAttempt: load.retryAttempt) }
        .task(id: phase.expiration) {
            if let expiry = phase.expiration {
                await model.graph.observeExpiration(for: snapshot, at: expiry)
            }
        }
    }

    private func refreshGraph(_ snapshot: RecommendationGraphSnapshot) {
        Task { await model.refreshSnapshot(requestID: snapshot.requestID) }
    }

    @ViewBuilder
    private func results(_ snapshot: DishesSnapshot) -> some View {
        let first = snapshot.firstPage
        if snapshot.items.isEmpty {
            ContentUnavailableView {
                Label("Блюда не найдены", systemImage: "magnifyingglass")
            } actions: {
                if model.filter != .all || !model.query.isEmpty || model.advancedFilters != DishesAdvancedFilters() {
                    Button("Сбросить поиск и фильтры") {
                        model.query = ""
                        model.filter = .all
                        model.apply(DishesAdvancedFilters())
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

        DishesNextPage(snapshot: snapshot, model: model)
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
