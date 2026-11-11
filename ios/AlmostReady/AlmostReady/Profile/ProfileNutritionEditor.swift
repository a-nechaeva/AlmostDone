enum ProfileFoodType: CaseIterable {
    case unrestricted
    case vegetarian
    case vegan

    var title: String {
        switch self {
        case .unrestricted: "Без ограничений"
        case .vegetarian: "Вегетарианство"
        case .vegan: "Веганство"
        }
    }
}

enum ProfileAllergen: CaseIterable {
    case milkProtein
    case eggs
    case gluten
    case peanuts
    case nuts
    case fish
    case soy
    case sesame

    var title: String {
        switch self {
        case .milkProtein: "Молочный белок"
        case .eggs: "Яйца"
        case .gluten: "Глютен"
        case .peanuts: "Арахис"
        case .nuts: "Орехи"
        case .fish: "Рыба"
        case .soy: "Соя"
        case .sesame: "Кунжут"
        }
    }
}

struct ProfileNutritionSettings: Equatable {
    var foodType: ProfileFoodType = .unrestricted
    var isGlutenFree = false
    var isLactoseFree = false
    var hasDiabetes = false
    var allergens: Set<ProfileAllergen> = []
    var dietTableName = ""
}

struct ProfileNutritionEditor {
    private(set) var saved = ProfileNutritionSettings()
    private(set) var isEditing = false
    var draft = ProfileNutritionSettings()

    mutating func open() {
        draft = saved
        isEditing = true
    }

    mutating func save() {
        saved = draft
        isEditing = false
    }

    mutating func cancel() {
        draft = saved
        isEditing = false
    }
}
