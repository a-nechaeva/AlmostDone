struct RecipePresentation {
    struct Nutrition {
        let kilocalories: Int
        let protein: Int
        let fat: Int
        let carbohydrates: Int
    }

    let photoName: String
    let minutes: Int
    let nutrition: Nutrition?
    let allergens: [String]

    // The iOS demo recipes have no serving sizes or quantities for nutrition estimates.
    static let demo: [Recipe.ID: Self] = [
        "tomato-omelet": Self(
            photoName: "RecipeTomatoOmelet",
            minutes: 15,
            nutrition: nil,
            allergens: ["Яйца"]
        ),
        "tomato-cheese-pasta": Self(
            photoName: "RecipeTomatoCheesePasta",
            minutes: 20,
            nutrition: nil,
            allergens: ["Глютен", "Молоко"]
        )
    ]
}
