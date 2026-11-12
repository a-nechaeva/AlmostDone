import SwiftUI

struct ShoppingScreen: View {
    @Environment(\.floatingTabBarHeight) private var tabBarHeight

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
    private let onCoverChange: (Bool) -> Void

    init(
        items: [ShoppingItem] = [ShoppingDemoPlan.cheese],
        onOpenTab: ((AppTab) -> Void)? = nil,
        onCoverChange: @escaping (Bool) -> Void = { _ in }
    ) {
        _shopping = State(initialValue: ShoppingState(items: items))
        self.onOpenTab = onOpenTab
        self.onCoverChange = onCoverChange
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
                    .shoppingFont(14, lineHeight: 20)
                    .foregroundStyle(ShoppingColor.secondary)
                    .padding(.top, 8)
                shoppingList
                    .padding(.top, 36)
                total
                    .padding(.top, 32)
                Button("Подобрать покупки под бюджет", action: showBudget)
                    .buttonStyle(ShoppingActionStyle())
                    .padding(.top, 53)
                demoSuggestion
                    .padding(.top, 28)
            }
        }
        .safeAreaPadding(.bottom, tabBarHeight)
        .onChange(of: presentation != nil) { _, isPresented in
            onCoverChange(isPresented)
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

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .shoppingFont(14, weight: .medium, lineHeight: 20)
                                .foregroundStyle(.primary)
                            Text(item.quantity)
                                .shoppingFont(12, lineHeight: 17)
                                .foregroundStyle(ShoppingColor.secondary)
                            if let price = item.estimatedPrice {
                                Text("≈\(shoppingRubles(price))")
                                    .shoppingFont(16, weight: .bold, lineHeight: 22)
                                    .foregroundStyle(ShoppingColor.accent)
                                    .padding(.top, 20)
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
        VStack(alignment: .leading, spacing: 0) {
            Text("Итого примерно")
                .shoppingFont(14, lineHeight: 20)
                .foregroundStyle(ShoppingColor.secondary)

            if let amount = shopping.estimatedRemainingTotal {
                Text(shoppingRubles(amount))
                    .shoppingFont(32, weight: .bold, lineHeight: 45)
                    .padding(.top, 12)
                Text("Цены примерные, за упаковку. В магазине могут отличаться.")
                    .shoppingFont(12, lineHeight: 17)
                    .foregroundStyle(ShoppingColor.secondary)
                    .padding(.top, 3)
            } else {
                Text("Для части покупок цена неизвестна.")
                    .shoppingFont(14, lineHeight: 20)
                    .foregroundStyle(ShoppingColor.secondary)
                    .padding(.top, 8)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var demoSuggestion: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Пример одиночной покупки")
                    .shoppingFont(15, weight: .medium, lineHeight: 21)
                Text("В демоплане сыр открывает ещё два блюда.")
                    .shoppingFont(12, lineHeight: 17)
                    .foregroundStyle(ShoppingColor.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ShoppingColor.secondary)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .shoppingCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }

    private func purchasedPage(_ item: ShoppingItem) -> some View {
        NavigationStack {
            ShoppingPage {
                ShoppingHeading(title: "Покупка отмечена", subtitle: "\(item.name) · \(item.quantity)")
                HStack(alignment: .top, spacing: 14) {
                    purchaseMark(isPurchased: true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Куплено")
                            .shoppingFont(14, weight: .medium, lineHeight: 20)
                        if let price = item.estimatedPrice {
                            Text("≈\(shoppingRubles(price)) за упаковку")
                                .shoppingFont(12, lineHeight: 17)
                                .foregroundStyle(ShoppingColor.secondary)
                        }
                    }
                }
                .padding(.vertical, 13)
                .frame(minHeight: 64, alignment: .topLeading)
                .accessibilityElement(children: .combine)
                .padding(.top, 46)

                ShoppingNotice(
                    title: "Готово",
                    message: "Покупка отмечена в списке. Продукты дома можно изменить отдельно."
                )
                .padding(.top, 40)

                Button("Вернуть в список") {
                    shopping.setPurchased(false, id: item.id)
                    presentation = nil
                }
                .buttonStyle(ShoppingActionStyle(isSecondary: true))
                .accessibilityHint("Снимает отметку о покупке")
                .padding(.top, 50)

                Button(onOpenTab == nil ? "К списку покупок" : "Мои продукты") {
                    closePurchase(opening: onOpenTab == nil ? .shopping : .products)
                }
                .buttonStyle(ShoppingActionStyle())
                .padding(.top, 16)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if onOpenTab != nil {
                    FloatingTabBar(
                        selection: .shopping,
                        accessibilityNamespace: "purchased.tabs",
                        onSelect: closePurchase(opening:)
                    )
                }
            }
            .rootScreenHeader()
        }
    }

    private func purchaseMark(isPurchased: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(ShoppingColor.outline, lineWidth: isPurchased ? 0 : 1)
            .background(
                isPurchased ? ShoppingColor.action : Color.clear,
                in: .rect(cornerRadius: 6)
            )
            .frame(width: 22, height: 22)
            .overlay {
                if isPurchased {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                }
            }
            .accessibilityHidden(true)
    }

    private func showBudget() {
        presentation = .budget
    }

    private func closePurchase(opening tab: AppTab) {
        tabAfterDismissal = tab == .shopping ? nil : tab
        presentation = nil
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
