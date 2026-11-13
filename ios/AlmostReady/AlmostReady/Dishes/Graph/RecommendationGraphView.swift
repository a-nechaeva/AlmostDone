import Accessibility
import SwiftUI

struct RecommendationGraphView: View {
    @State private var failedSetID: String?

    let phase: RecommendationGraphModel.Phase
    let onRetry: () -> Void
    let onRefreshSnapshot: () -> Void
    let onOpenRecipe: (RecipeRequest) -> Void
    var shoppingState: ([ShoppingPackage], AccountRevision) -> ServerShoppingModel.SuggestionAddition? = { _, _ in .add
    }
    let onAddSet: ([ShoppingPackage], AccountRevision) -> Bool

    var shoppingUnavailable = false

    var body: some View {
        switch phase {
        case .loading:
            ProgressView("Загружаем граф…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        case .loaded(let content):
            if content.isEmpty {
                ContentUnavailableView {
                    Label("В графе нет блюд", systemImage: "fork.knife")
                } description: {
                    if content.hasUnrepresentedDishes {
                        Text("Остальные блюда доступны в режиме «Список».")
                    }
                }
            } else {
                graph(content)
            }
        case .failed:
            ContentUnavailableView {
                Label("Не удалось загрузить граф", systemImage: "exclamationmark.circle")
            } actions: {
                Button("Повторить", action: onRetry)
            }
        case .refreshSnapshot:
            ContentUnavailableView {
                Label("Нужно обновить подбор", systemImage: "arrow.clockwise")
            } actions: {
                Button("Обновить подбор", action: onRefreshSnapshot)
            }
        }
    }

    private func graph(_ content: RecommendationGraphContent) -> some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(content.homeTitle)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if content.homeDishes.isEmpty {
                    Text("Нет блюд без докупки")
                        .foregroundStyle(.secondary)
                }
                ForEach(content.homeDishes, content: dish)
            }
            .graphCard()

            if content.purchaseSets.isEmpty {
                Text("Наборов для докупки нет")
                    .foregroundStyle(.secondary)
            }
            if shoppingUnavailable, failedSetID == nil {
                Text("Не удалось сохранить или открыть список покупок.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(content.purchaseSets) { set in
                purchaseSet(set, revision: content.revision)
            }
            if content.hasUnrepresentedDishes {
                Text("Остальные блюда доступны в режиме «Список».")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func purchaseSet(
        _ set: RecommendationGraphContent.PurchaseSet, revision: AccountRevision
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(set.title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(set.items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                    Text(item.quantityLabel)
                    Text(price(item.totalPrice))
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }

            Text(set.cost.map { "Всего \(shoppingRubles($0.rubles))" } ?? "Стоимость набора неизвестна")
                .font(.subheadline.weight(.semibold))

            ForEach(set.extensions) { path in
                let added = path.items.map { "\($0.name) (\($0.quantityLabel))" }.joined(separator: ", ")
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("От «\(path.from)» добавить \(added)")
                        Text(price(path.cost))
                    }
                } icon: {
                    Image(systemName: "arrow.turn.down.right")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Каждое блюдо можно приготовить по отдельности")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(set.dishes, content: dish)
            }

            shoppingAction(for: set, revision: revision)
        }
        .graphCard()
    }

    @ViewBuilder
    private func shoppingAction(
        for set: RecommendationGraphContent.PurchaseSet, revision: AccountRevision
    ) -> some View {
        if let action = shoppingState(set.items, revision) {
            let title: LocalizedStringKey =
                switch action {
                case .add: "Добавить набор в покупки"
                case .update: "Обновить список покупок"
                case .alreadyAdded: "Уже в покупках"
                case .marked: "Сначала снимите отметку «Куплено»"
                case .needsFreshSnapshot: "Обновить подбор"
                case .transferPending: "Завершите перенос в запасы"
                }
            Button(title) {
                if action == .needsFreshSnapshot {
                    onRefreshSnapshot()
                } else {
                    failedSetID = addSet(set, revision: revision) ? nil : set.id
                    if failedSetID != nil {
                        AccessibilityNotification.Announcement("Не удалось сохранить набор.").post()
                    }
                }
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .disabled(action != .add && action != .update && action != .needsFreshSnapshot)
            .accessibilityIdentifier("dishes.graph.add.\(set.id)")
            if failedSetID == set.id {
                Text("Не удалось сохранить набор.").font(.footnote)
            }
        }
    }

    private func dish(_ dish: RecommendationGraphContent.Dish) -> some View {
        Button {
            openRecipe(dish)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(dish.card.title)
                    .font(.subheadline.weight(.medium))
                if dish.card.suitability.status == .unknown {
                    Text("Пригодность неизвестна")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(dish.card.suitability.reasons.indices, id: \.self) { index in
                    Text(dish.card.suitability.reasons[index].message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !dish.card.availability.unknownQuantityIDs.isEmpty {
                    Text("У некоторых продуктов дома не указано количество")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
        .accessibilityIdentifier("dishes.graph.recipe.\(dish.request.id)")
    }

    func openRecipe(_ dish: RecommendationGraphContent.Dish) {
        onOpenRecipe(dish.request)
    }

    @discardableResult
    func addSet(_ set: RecommendationGraphContent.PurchaseSet, revision: AccountRevision) -> Bool {
        onAddSet(set.items, revision)
    }

    private func price(_ money: ShoppingMoney?) -> String {
        money.map { shoppingRubles($0.rubles) } ?? "Цена неизвестна"
    }
}

extension View {
    fileprivate func graphCard() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
}
