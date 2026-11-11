import Foundation

enum ProductsSearch {
    static func matches(_ query: String, excluding productIDs: Set<Ingredient.ID>) -> [Ingredient] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return DemoData.ingredients.filter { ingredient in
            !productIDs.contains(ingredient.id) && (term.isEmpty || ingredient.name.localizedStandardContains(term))
        }
    }
}
