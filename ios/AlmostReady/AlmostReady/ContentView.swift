import SwiftUI

enum Route: Hashable {
    case dishes
    case recipe(Recipe.ID)
}

struct ContentView: View {
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            ProductsScreen()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .dishes:
                        DishesScreen()
                    case .recipe(let id):
                        RecipeScreen(recipeID: id)
                    }
                }
        }
    }
}
