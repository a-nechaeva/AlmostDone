import SwiftUI

struct ContentView: View {
    @State private var selection = AppTab.products
    @State private var dishPath: [Recipe.ID] = []

    var body: some View {
        TabView(selection: $selection) {
            tab(.products) {
                NavigationStack {
                    ProductsScreen(onOpenDishes: openDishes, tabBar: tabBar)
                }
            }
            tab(.dishes) {
                NavigationStack(path: $dishPath) {
                    DishesScreen(onOpenProducts: openProducts, tabBar: tabBar)
                        .navigationDestination(for: Recipe.ID.self) { id in
                            RecipeScreen(recipeID: id)
                                .toolbar(.visible, for: .navigationBar)
                        }
                }
            }
            tab(.shopping) {
                NavigationStack {
                    ShoppingScreen(onOpenTab: selectTab)
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

    private var tabBar: FloatingTabBar {
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

    private func openDishes() {
        dishPath.removeAll()
        selection = .dishes
    }

    private func selectTab(_ tab: AppTab) {
        selection = tab
    }
}
