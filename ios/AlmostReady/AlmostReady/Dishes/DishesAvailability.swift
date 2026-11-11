struct DishesAvailability {
    struct Entry: Identifiable {
        var id: Recipe.ID { recipe.id }
        let recipe: Recipe
        let missingIngredients: [Ingredient]
    }

    let ready: [Entry]
    let needsShopping: [Entry]

    var isEmpty: Bool {
        ready.isEmpty && needsShopping.isEmpty
    }

    init(recipes: [Recipe], missingIngredients: (Recipe) -> [Ingredient]) {
        var ready: [Entry] = []
        var needsShopping: [Entry] = []

        for recipe in recipes {
            let missing = missingIngredients(recipe)
            let entry = Entry(recipe: recipe, missingIngredients: missing)
            switch missing.count {
            case 0:
                ready.append(entry)
            case 1...3:
                needsShopping.append(entry)
            default:
                break
            }
        }

        self.ready = ready
        self.needsShopping = needsShopping
    }
}
