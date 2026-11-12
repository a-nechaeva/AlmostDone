import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var session: SessionStore?

    @State private var selection = AppTab.products
    @State private var tabBarHeight: CGFloat = 0
    @State private var isProductsSearchPresented = false
    @State private var dishPath: [RecipeRequest] = []
    @FocusState private var isDishSearchFocused: Bool
    @State private var isShoppingCoverPresented = false
    @State private var isNutritionPresented = false

    var body: some View {
        TabView(selection: $selection) {
            tab(.products) {
                if let session {
                    if let account = session.account {
                        ServerProductsTab(
                            repository: ProductsRepository(session: session, account: account),
                            isSearchPresented: $isProductsSearchPresented,
                            onOpenDishes: openDishes
                        )
                    }
                } else {
                    NavigationStack {
                        ProductsScreen(isSearchPresented: $isProductsSearchPresented, onOpenDishes: openDishes)
                    }
                }
            }
            tab(.dishes) {
                NavigationStack(path: $dishPath) {
                    Group {
                        if let session {
                            if let account = session.account {
                                ServerDishesScreen(
                                    repository: RecommendationsRepository(session: session, account: account),
                                    isSearchFocused: $isDishSearchFocused,
                                    onOpenProducts: openProducts
                                )
                                .id(account.id)
                            }
                        } else {
                            DishesScreen(isSearchFocused: $isDishSearchFocused, onOpenProducts: openProducts)
                        }
                    }
                    .navigationDestination(for: RecipeRequest.self) { request in
                        RecipeScreen(
                            recipeID: request.id, servings: request.servings,
                            excludedAllergenIDs: request.excludedAllergenIDs
                        )
                        .toolbar(.visible, for: .navigationBar)
                    }
                }
            }
            tab(.shopping) {
                NavigationStack {
                    if session != nil {
                        serverPlaceholder(.shopping)
                    } else {
                        ShoppingScreen(onOpenTab: selectTab) { isPresented in
                            isShoppingCoverPresented = isPresented
                        }
                    }
                }
            }
            tab(.profile) {
                NavigationStack {
                    ProfileScreen(onOpenProducts: openProducts) { isPresented in
                        isNutritionPresented = isPresented
                    }
                }
            }
        }
        .environment(\.floatingTabBarHeight, showsTabBar ? tabBarHeight : 0)
        .overlay(alignment: .bottom) {
            if showsTabBar {
                FloatingTabBar(selection: selection, onSelect: selectTab)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                        // Reserve space inside the tab's scroll view, across the navigation hosting boundary.
                        tabBarHeight = height
                    }
            }
        }
    }

    private func serverPlaceholder(_ tab: AppTab) -> some View {
        VStack(spacing: 12) {
            RootScreenTitle(tab: tab)
            Text("Экран пока недоступен в серверном режиме")
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }

    private var showsTabBar: Bool {
        switch selection {
        case .products: !isProductsSearchPresented
        case .dishes: dishPath.isEmpty && !isDishSearchFocused
        case .shopping: !isShoppingCoverPresented
        case .profile: !isNutritionPresented
        }
    }

    private func tab<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .toolbar(.hidden, for: .tabBar)
            .tabItem { Text(tab.title) }
            .tag(tab)
    }

    private func openProducts() {
        selectTab(.products)
    }

    private func openDishes() {
        dishPath.removeAll()
        selectTab(.dishes)
    }

    private func selectTab(_ tab: AppTab) {
        selection = tab
    }
}
