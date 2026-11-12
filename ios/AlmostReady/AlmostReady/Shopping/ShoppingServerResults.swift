import SwiftUI

struct ShoppingServerResults: View {
    let model: ServerShoppingRecommendationModel
    let kind: ShoppingRecommendationKind
    let onAdd: () -> Void
    let onRetry: () -> Void

    var body: some View {
        switch model.recommendation {
        case .idle, .invalidBudget:
            EmptyView()
        case .loading:
            ProgressView("Подбираем покупки…")
        case .unavailable:
            VStack(spacing: 12) {
                notice("Сервис временно недоступен", "Бюджет и число порций сохранены.")
                Button("Повторить", action: onRetry)
                    .buttonStyle(ShoppingActionStyle())
            }
        case .result(let result):
            switch result.status {
            case .noPlan:
                notice("Подходящих покупок нет", "Попробуйте изменить бюджет или число порций.")
            case .insufficientData:
                notice("Недостаточно данных", "Для расчёта не хватает сведений о ценах или упаковках.")
            case .found:
                suggestions(result)
            }
        }
    }

    private func suggestions(_ result: ShoppingRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ShoppingHeading(title: kind == .budget ? "План на ваш бюджет" : "Варианты покупки")
            Text(
                kind == .budget
                    ? "Из покупок можно приготовить любое из предложенных блюд по отдельности."
                    : "Каждый вариант рассчитан отдельно. Цены вариантов не складываются."
            )
            .foregroundStyle(ShoppingColor.secondary)

            ForEach(result.suggestions) { suggestion in
                suggestionCard(suggestion)
            }

            if result.hasUnpricedRecipes {
                Text("Часть блюд пропущена, потому что для них не удалось рассчитать стоимость.")
                    .font(.footnote)
                    .foregroundStyle(ShoppingColor.secondary)
            }
        }
    }

    private func suggestionCard(_ suggestion: ShoppingSuggestion) -> some View {
        let addition = model.addition(for: suggestion)
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(suggestion.items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.headline)
                    Text(item.quantityLabel)
                    if let price = item.totalPrice {
                        Text(shoppingRubles(price.rubles))
                    } else {
                        Text("Цена неизвестна")
                    }
                    if addition != .alreadyAdded && model.contains(item) {
                        Text("Уже в покупках").foregroundStyle(ShoppingColor.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            if kind == .budget, let total = suggestion.totalCost {
                Text("Всего \(shoppingRubles(total.rubles))").font(.headline)
            }

            Text("Варианты блюд: \(suggestion.unlockedRecipeCount)")
                .foregroundStyle(ShoppingColor.secondary)

            Button(additionTitle(addition)) {
                if model.add(suggestion, undoable: kind == .budget) { onAdd() }
            }
            .buttonStyle(ShoppingActionStyle(isSecondary: true))
            .disabled(addition != .add && addition != .update)

            if model.storageUnavailable {
                Text("Не удалось сохранить список покупок.").font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .shoppingCard(cornerRadius: 18)
    }

    private func additionTitle(_ addition: ServerShoppingModel.SuggestionAddition) -> LocalizedStringKey {
        switch addition {
        case .add: "Добавить в список"
        case .update: "Обновить список покупок"
        case .alreadyAdded: "Уже в покупках"
        case .marked: "Сначала снимите отметку «Куплено»"
        case .needsFreshSnapshot: "Подберите покупки заново"
        case .transferPending: "Завершите перенос в запасы"
        }
    }

    private func notice(_ title: LocalizedStringKey, _ message: LocalizedStringKey) -> some View {
        ShoppingNotice(title: title, message: message, isWarning: true)
            .accessibilityIdentifier("shopping.budget.status")
    }
}
