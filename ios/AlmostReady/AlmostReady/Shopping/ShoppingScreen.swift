import SwiftUI

struct ShoppingScreen: View {
    private enum Presentation: Identifiable {
        case budget
        case purchased(ShoppingItem)

        var id: String {
            switch self {
            case .budget: "budget"
            case .purchased(let item): "purchased.\(item.id)"
            }
        }
    }

    @State private var shopping: ShoppingState
    @State private var presentation: Presentation?
    @State private var tabAfterDismissal: AppTab?
    private let onOpenTab: ((AppTab) -> Void)?

    init(items: [ShoppingItem] = [ShoppingDemoPlan.cheese], onOpenTab: ((AppTab) -> Void)? = nil) {
        _shopping = State(initialValue: ShoppingState(items: items))
        self.onOpenTab = onOpenTab
    }

    var body: some View {
        ShoppingPage {
            RootScreenTitle(tab: .shopping)

            if shopping.items.isEmpty {
                ShoppingEmptyState(
                    title: "Список пока пуст",
                    message: "Подберите покупки на свой бюджет.",
                    buttonTitle: "Подобрать покупки",
                    action: showBudget
                )
                .padding(.top, 100)
            } else {
                Text("Из выбранных рецептов")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                shoppingList
                    .padding(.top, 36)
                total
                    .padding(.top, 32)
                Button("Подобрать покупки под бюджет", action: showBudget)
                    .buttonStyle(ShoppingActionStyle())
                    .padding(.top, 48)
                demoSuggestion
                    .padding(.top, 28)
            }
        }
        .floatingTabBarInset {
            if let onOpenTab {
                FloatingTabBar(selection: .shopping, onSelect: onOpenTab)
                    .accessibilityHidden(presentation != nil)
            }
        }
        .rootScreenHeader()
        .fullScreenCover(item: $presentation, onDismiss: openTabAfterDismissal) { destination in
            switch destination {
            case .budget:
                NavigationStack {
                    ShoppingBudgetScreen(
                        input: $shopping.budgetInput,
                        hasDemoPlan: shopping.hasDemoPlan
                    ) {
                        shopping.addDemoPlan()
                        presentation = nil
                    }
                }
            case .purchased(let item):
                purchasedPage(item)
            }
        }
    }

    private var shoppingList: some View {
        LazyVStack(spacing: 10) {
            ForEach(shopping.items) { item in
                Button {
                    if let changed = shopping.setPurchased(!item.isPurchased, id: item.id), changed.isPurchased {
                        presentation = .purchased(changed)
                    }
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        purchaseMark(isPurchased: item.isPurchased)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(item.quantity)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let price = item.estimatedPrice {
                                Text("≈\(shoppingRubles(price))")
                                    .font(.headline)
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.top, 18)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                    .frame(minHeight: 56)
                    .shoppingCard(cornerRadius: 24)
                    .contentShape(.rect(cornerRadius: 24))
                }
                .buttonStyle(.plain)
                .accessibilityValue(item.isPurchased ? Text("Куплено") : Text("К покупке"))
                .accessibilityHint(item.isPurchased ? Text("Снять отметку") : Text("Отметить покупку"))
                .accessibilityIdentifier("shopping.item.\(item.id)")
            }
        }
    }

    private var total: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Итого примерно")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let amount = shopping.estimatedRemainingTotal {
                Text(shoppingRubles(amount))
                    .font(.largeTitle.bold())
                Text("Цены примерные, за упаковку. В магазине могут отличаться.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Для части покупок цена неизвестна.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var demoSuggestion: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Пример одиночной покупки")
                    .font(.subheadline.weight(.medium))
                Text("В демоплане сыр открывает ещё два блюда.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .shoppingCard()
        .accessibilityElement(children: .combine)
    }

    private func purchasedPage(_ item: ShoppingItem) -> some View {
        NavigationStack {
            ShoppingPage {
                ShoppingHeading(title: "Покупка отмечена", subtitle: "\(item.name) · \(item.quantity)")
                HStack(spacing: 14) {
                    purchaseMark(isPurchased: true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Куплено")
                            .font(.subheadline.weight(.medium))
                        if let price = item.estimatedPrice {
                            Text("≈\(shoppingRubles(price)) за упаковку")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .padding(.top, 52)

                ShoppingNotice(
                    title: "Готово",
                    message: "Покупка отмечена в списке. Продукты дома можно изменить отдельно."
                )
                .padding(.top, 48)

                Button("Снять отметку") {
                    shopping.setPurchased(false, id: item.id)
                    presentation = nil
                }
                .buttonStyle(ShoppingActionStyle(isSecondary: true))
                .padding(.top, 48)

                Button("К списку покупок") {
                    presentation = nil
                }
                .buttonStyle(ShoppingActionStyle())
                .padding(.top, 16)
            }
            .floatingTabBarInset {
                if onOpenTab != nil {
                    FloatingTabBar(selection: .shopping, accessibilityNamespace: "purchased.tabs") { tab in
                        guard tab != .shopping else { return }
                        tabAfterDismissal = tab
                        presentation = nil
                    }
                }
            }
            .navigationTitle("Покупки")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func purchaseMark(isPurchased: Bool) -> some View {
        Image(systemName: isPurchased ? "checkmark.square.fill" : "square")
            .font(.title3)
            .foregroundStyle(isPurchased ? Color.accentColor : Color.secondary)
            .accessibilityHidden(true)
    }

    private func showBudget() {
        presentation = .budget
    }

    private func openTabAfterDismissal() {
        guard let tab = tabAfterDismissal else { return }
        tabAfterDismissal = nil
        onOpenTab?(tab)
    }
}

#Preview("Покупки") {
    NavigationStack {
        ShoppingScreen()
    }
}

#Preview("Пустой список покупок") {
    NavigationStack {
        ShoppingScreen(items: [])
    }
}
