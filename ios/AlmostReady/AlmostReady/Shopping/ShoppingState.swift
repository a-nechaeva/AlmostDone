import Foundation

struct ShoppingItem: Identifiable {
    let id: String
    let name: String
    let quantity: String
    let estimatedPrice: Decimal?
    var isPurchased = false
}

struct ShoppingState {
    var budgetInput = "500"
    private(set) var items: [ShoppingItem]

    init(items: [ShoppingItem] = [ShoppingDemoPlan.cheese]) {
        self.items = items
    }

    var hasDemoPlan: Bool {
        items.contains { $0.id == ShoppingDemoPlan.cheese.id }
    }

    var estimatedRemainingTotal: Decimal? {
        let remaining = items.filter { !$0.isPurchased }
        let prices = remaining.compactMap(\.estimatedPrice)
        guard prices.count == remaining.count else { return nil }
        return prices.reduce(0, +)
    }

    @discardableResult
    mutating func setPurchased(_ isPurchased: Bool, id: ShoppingItem.ID) -> ShoppingItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        items[index].isPurchased = isPurchased
        return items[index]
    }

    mutating func addDemoPlan() {
        guard !hasDemoPlan else { return }
        items.append(ShoppingDemoPlan.cheese)
    }
}

enum ShoppingDemoPlan {
    static let price: Decimal = 230
    static let cheese = ShoppingItem(
        id: "hard-cheese",
        name: "Сыр твёрдый",
        quantity: "Упаковка 200 г",
        estimatedPrice: price
    )
}

enum ShoppingBudgetError: Error, Equatable {
    case empty
    case zero
    case invalid
}

enum ShoppingBudgetResult: Hashable {
    case example(budget: Decimal)
    case unavailable(budget: Decimal)

    static func evaluate(_ input: String) -> Result<Self, ShoppingBudgetError> {
        let amount = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !amount.isEmpty else { return .failure(.empty) }

        let pattern = #"^(?:[0-9]+|[0-9]{1,3}(?:[ \u00A0\u202F\u2009][0-9]{3})+)(?:[,.][0-9]{1,2})?$"#
        guard amount.range(of: pattern, options: .regularExpression) != nil else { return .failure(.invalid) }

        let parts = amount.split(whereSeparator: { $0 == "," || $0 == "." })
        guard let rubles = Int(parts[0].filter { !$0.isWhitespace }) else { return .failure(.invalid) }
        let fraction = parts.dropFirst().first ?? ""
        let kopecks = Int(fraction) ?? 0
        let budget = Decimal(rubles) + Decimal(kopecks) / (fraction.count == 1 ? 10 : 100)
        guard budget > 0 else { return .failure(.zero) }

        return .success(budget >= ShoppingDemoPlan.price ? .example(budget: budget) : .unavailable(budget: budget))
    }
}

func shoppingRubles(_ amount: Decimal) -> String {
    amount.formatted(.currency(code: "RUB").precision(.fractionLength(0...2)).locale(Locale(identifier: "ru_RU")))
}
