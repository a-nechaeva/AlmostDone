import Foundation

struct RecipePresentation {
    struct Nutrition {
        let kilocalories: String
        let macros: String
    }

    struct Servings {
        let count: Int

        var unit: String {
            RecipePresentation.countedUnit(count, one: "порция", few: "порции", many: "порций")
        }

        var description: String { "\(count) \(unit)" }

        var ingredientCaption: String {
            let unit = RecipePresentation.countedUnit(count, one: "порцию", few: "порции", many: "порций")
            return "На \(count) \(unit)"
        }
    }

    enum Availability {
        case ready
        case missing(Int)
        case unknown(missingCount: Int)

        var label: String {
            switch self {
            case .ready: "Все продукты есть"
            case .missing(let count): RecipePresentation.shoppingBadge(missingCount: count)
            case .unknown(let count) where count > 0:
                "\(RecipePresentation.shoppingBadge(missingCount: count)). По остальным продуктам данных недостаточно"
            case .unknown: "Наличие продуктов неизвестно"
            }
        }

        var icon: String {
            switch self {
            case .ready: "checkmark"
            case .missing: "bag"
            case .unknown: "questionmark"
            }
        }
    }

    struct IngredientRow: Identifiable {
        let id: String
        let name: String
        let availability: RecipeDetailDTO.Ingredient.Availability
        let status: String
        let amount: String?
        let originalAmountNote: String?
    }

    struct Step {
        let number: Int
        let text: String
        let minutes: Int?
    }

    struct Purchase: Identifiable {
        let id: String
        let name: String
        let packages: String
        let price: String
    }

    let title: String
    let minutes: Int?
    let servings: Servings?
    let nutrition: Nutrition?
    let allergens: [String]
    let allergenNote: String?
    let suitabilityNotes: [String]
    let availability: Availability
    let ingredients: [IngredientRow]
    let steps: [Step]
    let purchases: [Purchase]
    let costCaption: String
    let cost: String

    private static let demoMetadata: [Recipe.ID: (photoName: String, minutes: Int, allergens: [String])] = [
        "tomato-omelet": ("RecipeTomatoOmelet", 15, ["Яйца"]),
        "tomato-cheese-pasta": ("RecipeTomatoCheesePasta", 20, ["Глютен", "Молоко"])
    ]

    static func demoPhotoName(for id: Recipe.ID) -> String? {
        demoMetadata[id]?.photoName
    }

    init(demo recipe: Recipe, missingIDs: Set<Ingredient.ID>) {
        let metadata = Self.demoMetadata[recipe.id]
        let demoPrice = missingIDs == [DemoData.cheese.id] ? ShoppingDemoPlan.cheese.estimatedPrice : nil
        title = recipe.title
        minutes = metadata?.minutes
        servings = nil
        nutrition = nil
        allergens = metadata?.allergens ?? []
        allergenNote = nil
        suitabilityNotes = []
        availability = missingIDs.isEmpty ? .ready : .missing(missingIDs.count)
        ingredients = recipe.ingredients.map { ingredient in
            let isMissing = missingIDs.contains(ingredient.id)
            return IngredientRow(
                id: ingredient.id, name: ingredient.name, availability: isMissing ? .missing : .enough,
                status: isMissing ? "Нужно докупить" : "Есть дома", amount: nil, originalAmountNote: nil
            )
        }
        steps = recipe.steps.enumerated().map { Step(number: $0.offset + 1, text: $0.element, minutes: nil) }
        purchases = []
        costCaption = demoPrice == nil ? "Докупка" : "За упаковку"
        cost = demoPrice.map { "≈\(shoppingRubles($0))" } ?? (missingIDs.isEmpty ? "Не нужна" : "Нужна")
    }

    init(detail: RecipeDetailDTO) {
        let card = detail.recipe
        title = card.title
        minutes = card.minutes
        servings = Servings(count: card.servings)
        nutrition = card.nutrition.map {
            Nutrition(
                kilocalories: Self.number($0.kcal),
                macros: "Б \(Self.number($0.protein)) г · Ж \(Self.number($0.fat)) г · У \(Self.number($0.carbs)) г"
            )
        }
        allergens = card.allergens.contains.map { Self.allergenNames[$0] ?? $0 }
        switch card.allergens.completeness {
        case .complete: allergenNote = allergens.isEmpty ? "По данным рецепта, аллергенов нет" : nil
        case .incomplete: allergenNote = "Сведения об аллергенах неполные"
        case .unknown: allergenNote = "Сведения об аллергенах неизвестны"
        }
        suitabilityNotes = card.suitability.reasons.map(\.message)
        switch card.availability.status {
        case .ready: availability = .ready
        case .missing: availability = .missing(card.availability.missingCount)
        case .unknown: availability = .unknown(missingCount: card.availability.missingCount)
        }
        let unknownQuantityIDs = Set(card.availability.unknownQuantityIDs)
        let skipOptionalIDs = Set(
            card.suitability.reasons.filter { $0.code == "skip_optional" }.flatMap(\.ingredientIDs))
        ingredients = detail.ingredients.map { ingredient in
            let amount = ingredient.required.map(Self.quantity)
            let originalAmountNote =
                amount == nil ? ingredient.originalAmount.map { "\($0) (в исходном рецепте)" } : nil
            let status =
                skipOptionalIDs.contains(ingredient.id)
                ? "По желанию. Лучше исключить"
                : Self.ingredientStatus(ingredient, isHomeQuantityUnknown: unknownQuantityIDs.contains(ingredient.id))
            return IngredientRow(
                id: ingredient.id, name: ingredient.name, availability: ingredient.availability, status: status,
                amount: amount, originalAmountNote: originalAmountNote
            )
        }
        steps = detail.steps.sorted { $0.number < $1.number }.map {
            Step(number: $0.number, text: $0.text, minutes: $0.minutes)
        }
        purchases = detail.shoppingItems.map {
            Purchase(
                id: $0.key, name: $0.name, packages: "\($0.packageCount) × \(Self.quantity($0.packageQuantity))",
                price: $0.totalPrice.map(Self.money) ?? "Цена неизвестна"
            )
        }
        costCaption = "Докупка"
        cost = card.buyCost.map(Self.money) ?? "Цена неизвестна"
    }

    private static func ingredientStatus(
        _ ingredient: RecipeDetailDTO.Ingredient, isHomeQuantityUnknown: Bool
    ) -> String {
        var status: String
        switch ingredient.availability {
        case .enough:
            status = isHomeQuantityUnknown ? "Есть дома, количество неизвестно" : "Есть дома"
        case .missing:
            status = ingredient.shortage.map { "Нужно докупить \(quantity($0))" } ?? "Нужно докупить"
            if let available = ingredient.available, available.value > 0 {
                status = "Дома \(quantity(available)). \(status)"
            }
        case .unknown:
            status = "Данных о наличии недостаточно"
        case .optional:
            return "По желанию"
        }
        return ingredient.optional ? "По желанию. \(status)" : status
    }

    private static func number(_ value: Decimal) -> String {
        value.formatted(.number.locale(Locale(identifier: "ru_RU")))
    }

    private static func quantity(_ value: RecipeDetailDTO.Quantity) -> String {
        let unit =
            switch value.unit {
            case .g: "г"
            case .ml: "мл"
            case .pcs: "шт."
            }
        return "\(number(value.value)) \(unit)"
    }

    private static func money(_ value: RecipeDetailDTO.Money) -> String {
        shoppingRubles(Decimal(value.minorUnits) / 100)
    }

    private static func shoppingBadge(missingCount: Int) -> String {
        let unit = countedUnit(missingCount, one: "продукт", few: "продукта", many: "продуктов")
        return "Нужно докупить \(missingCount) \(unit)"
    }

    private static func countedUnit(_ count: Int, one: String, few: String, many: String) -> String {
        if (11...14).contains(count % 100) {
            return many
        }
        switch count % 10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }

    private static let allergenNames = [
        "gluten": "Глютен", "milk": "Молочный белок", "eggs": "Яйца", "fish": "Рыба",
        "crustaceans": "Ракообразные", "molluscs": "Моллюски", "peanuts": "Арахис",
        "nuts": "Орехи", "soy": "Соя", "sesame": "Кунжут", "mustard": "Горчица",
        "celery": "Сельдерей", "lupin": "Люпин", "sulphites": "Сульфиты"
    ]
}
