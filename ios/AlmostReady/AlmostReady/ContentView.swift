import SwiftUI

struct ContentView: View {
    @State private var selection = AppTab.products
    @State private var tabBarHeight: CGFloat = 0
    @State private var isProductsSearchPresented = false
    @State private var dishPath: [Recipe.ID] = []
    @FocusState private var isDishSearchFocused: Bool
    @State private var isShoppingCoverPresented = false
    @State private var isNutritionPresented = false

    var body: some View {
        TabView(selection: $selection) {
            tab(.products) {
                NavigationStack {
                    ProductsScreen(isSearchPresented: $isProductsSearchPresented, onOpenDishes: openDishes)
                }
            }
            tab(.dishes) {
                NavigationStack(path: $dishPath) {
                    DishesScreen(isSearchFocused: $isDishSearchFocused, onOpenProducts: openProducts)
                        .navigationDestination(for: Recipe.ID.self) { id in
                            RecipeScreen(recipeID: id)
                                .toolbar(.visible, for: .navigationBar)
                        }
                }
            }
            tab(.shopping) {
                NavigationStack {
                    ShoppingScreen(onOpenTab: selectTab) { isPresented in
                        isShoppingCoverPresented = isPresented
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
