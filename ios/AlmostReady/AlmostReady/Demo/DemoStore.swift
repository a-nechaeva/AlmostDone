import Observation

@Observable
final class DemoStore {
    var productIDs = DemoData.initialProductIDs
    let recipes = DemoData.recipes

    var products: [Ingredient] {
        DemoData.ingredients.filter { productIDs.contains($0.id) }
    }

    func recipe(id: Recipe.ID) -> Recipe? {
        recipes.first { $0.id == id }
    }

    func missingIngredients(for recipe: Recipe) -> [Ingredient] {
        recipe.ingredients.filter { !productIDs.contains($0.id) }
    }
}
