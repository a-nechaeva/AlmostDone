import SwiftUI

struct ContentView: View {
    @State private var selection = AppTab.products
    @State private var dishPath: [Recipe.ID] = []
    @FocusState private var searchFocus: AppTab?

    var body: some View {
        TabView(selection: $selection) {
            tab(.products) {
                NavigationStack {
                    ProductsScreen(searchFocus: $searchFocus) {
                        dishPath.removeAll()
                        selection = .dishes
                    }
                    .floatingTabBarInset {
                        if searchFocus != .products { tabBar }
                    }
                }
            }
            tab(.dishes) {
                NavigationStack(path: $dishPath) {
                    DishesScreen(searchFocus: $searchFocus, onOpenProducts: openProducts)
                        .floatingTabBarInset {
                            if searchFocus != .dishes { tabBar }
                        }
                        .navigationDestination(for: Recipe.ID.self) { id in
                            RecipeScreen(recipeID: id)
                        }
                }
            }
            tab(.shopping) {
                NavigationStack {
                    ShoppingScreen(onOpenTab: selectTab)
                        .floatingTabBarInset { tabBar }
                }
            }
            tab(.profile) {
                NavigationStack {
                    ProfileScreen(onOpenProducts: openProducts)
                        .floatingTabBarInset { tabBar }
                }
            }
        }
    }

    private var tabBar: some View {
        FloatingTabBar(selection: selection, onSelect: selectTab)
    }

    private func tab<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .toolbar(.hidden, for: .tabBar)
            .tabItem { Text(tab.title) }
            .tag(tab)
    }

    private func openProducts() {
        selection = .products
    }

    private func selectTab(_ tab: AppTab) {
        selection = tab
    }
}
