struct Ingredient: Identifiable {
    let id: String
    let name: String
}

struct Recipe: Identifiable {
    let id: String
    let title: String
    let ingredients: [Ingredient]
    let steps: [String]
}

enum DemoData {
    static let eggs = Ingredient(id: "eggs", name: "Яйца")
    static let tomatoes = Ingredient(id: "tomatoes", name: "Томаты")
    static let pasta = Ingredient(id: "pasta", name: "Макароны")
    static let cheese = Ingredient(id: "cheese", name: "Сыр")
    static let oliveOil = Ingredient(id: "olive-oil", name: "Оливковое масло")

    static let ingredients = [eggs, tomatoes, pasta, cheese, oliveOil]
    static let initialProductIDs: Set<Ingredient.ID> = [
        eggs.id, tomatoes.id, pasta.id, oliveOil.id
    ]

    static let recipes = [
        Recipe(
            id: "tomato-omelet",
            title: "Омлет с томатами",
            ingredients: [eggs, tomatoes, oliveOil],
            steps: [
                "Нарежьте томаты и слегка обжарьте их на оливковом масле.",
                "Взбейте яйца, влейте их в сковороду и готовьте под крышкой, пока омлет не схватится."
            ]
        ),
        Recipe(
            id: "tomato-cheese-pasta",
            title: "Паста с томатами и сыром",
            ingredients: [pasta, tomatoes, cheese, oliveOil],
            steps: [
                "Сварите макароны по инструкции на упаковке.",
                "Прогрейте нарезанные томаты на оливковом масле.",
                "Смешайте макароны с томатами и посыпьте тёртым сыром."
            ]
        )
    ]
}
