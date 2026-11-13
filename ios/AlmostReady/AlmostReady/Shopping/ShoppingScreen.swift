import SwiftUI

struct ShoppingScreen: View {
    @Environment(\.floatingTabBarHeight) private var tabBarHeight
    @Environment(ServerShoppingModel.self) private var server: ServerShoppingModel?

    private enum Presentation: Identifiable {
        case budget(ShoppingRecommendationKind)
        case transfer
        case purchased(ShoppingItem)

        var id: String {
            switch self {
            case .budget(let kind): kind.rawValue
            case .transfer: "transfer"
            case .purchased(let item): "purchased.\(item.id)"
            }
        }
    }

    @State private var shopping: ShoppingState
    @State private var presentation: Presentation?
    @State private var recommendations: ServerShoppingRecommendationModel?
    private let repository: ShoppingRepository?
    @State private var tabAfterDismissal: AppTab?
    private let onOpenTab: ((AppTab) -> Void)?
    private let onCoverChange: (Bool) -> Void

    init(
        items: [ShoppingItem] = [ShoppingDemoPlan.cheese],
        repository: ShoppingRepository? = nil,
        onOpenTab: ((AppTab) -> Void)? = nil,
        onCoverChange: @escaping (Bool) -> Void = { _ in }
    ) {
        _shopping = State(initialValue: ShoppingState(items: items))
        self.repository = repository
        self.onOpenTab = onOpenTab
        self.onCoverChange = onCoverChange
    }

    var body: some View {
        ShoppingPage {
            RootScreenTitle(tab: .shopping)

            if server?.storageUnavailable == true {
                Text("Не удалось сохранить или открыть список покупок.").foregroundStyle(.secondary)
                    .padding(.top, 12)
            }

            if items.isEmpty {
                ShoppingEmptyState(
                    title: "Список пока пуст",
                    message: "Подберите покупки на свой бюджет.",
                    buttonTitle: "Подобрать покупки",
                    action: { showBudget() }
                )
                .padding(.top, 100)
            } else {
                Text(server == nil ? "Из выбранных рецептов" : "Список покупок")
                    .shoppingFont(14, lineHeight: 20)
                    .foregroundStyle(ShoppingColor.secondary)
                    .padding(.top, 8)
                shoppingList
                    .padding(.top, 36)
                total
                    .padding(.top, 32)
                if let server, server.markedCount > 0 {
                    Button("Перенести купленное в запасы") { presentation = .transfer }
                        .buttonStyle(ShoppingActionStyle(isSecondary: true))
                        .padding(.top, 24)
                }
                if let server, server.canUndoPlan {
                    Button("Отменить добавление плана", action: server.undoPlan)
                        .buttonStyle(ShoppingActionStyle(isSecondary: true))
                        .accessibilityIdentifier("shopping.budget.undo")
                        .padding(.top, 24)
                }
                Button("Подобрать покупки под бюджет", action: { showBudget() })
                    .buttonStyle(ShoppingActionStyle())
                    .padding(.top, 53)
            }
            if server != nil {
                Button("Подобрать одиночную покупку") { showBudget(.singlePurchase) }
                    .buttonStyle(ShoppingActionStyle(isSecondary: true))
                    .padding(.top, 28)
            } else if !items.isEmpty {
                demoSuggestion
                    .padding(.top, 28)
            }
        }
        .safeAreaPadding(.bottom, tabBarHeight)
        .onChange(of: presentation != nil) { _, isPresented in
            onCoverChange(isPresented)
        }
        .rootScreenHeader(showsDemoLabel: server == nil)
        .fullScreenCover(item: $presentation, onDismiss: openTabAfterDismissal) { destination in
            switch destination {
            case .budget(let kind):
                NavigationStack {
                    ShoppingBudgetScreen(
                        input: budgetInput,
                        hasDemoPlan: shopping.hasDemoPlan,
                        server: recommendations,
                        kind: kind
                    ) {
                        if server == nil { shopping.addDemoPlan() }
                        presentation = nil
                    }
                }
            case .transfer:
                purchasedPage(nil)
            case .purchased(let item):
                purchasedPage(item)
            }
        }
    }

    private var items: [ShoppingItem] { server?.items ?? shopping.items }

    private var budgetInput: Binding<String> {
        guard let recommendations else { return $shopping.budgetInput }
        return Binding(get: { recommendations.budgetInput }, set: { recommendations.budgetInput = $0 })
    }

    private var shoppingList: some View {
        LazyVStack(spacing: 10) {
            ForEach(items) { item in
                Button {
                    if let changed = setPurchased(!item.isPurchased, id: item.id), changed.isPurchased {
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
                                Text(priceLabel(price))
                                    .shoppingFont(16, weight: .bold, lineHeight: 22)
                                    .foregroundStyle(ShoppingColor.accent)
                                    .padding(.top, 20)
                            } else {
                                Text("Цена неизвестна")
                                    .shoppingFont(12, lineHeight: 17)
                                    .foregroundStyle(ShoppingColor.secondary)
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
                .disabled(server?.isSelectionLocked == true)
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

            if let amount = ShoppingState(items: items).estimatedRemainingTotal {
                Text(shoppingRubles(amount))
                    .shoppingFont(32, weight: .bold, lineHeight: 45)
                    .padding(.top, 12)
                Text(
                    server == nil
                        ? "Цены примерные, за упаковку. В магазине могут отличаться."
                        : "Сумма за упаковки, которые осталось купить. В магазине могут отличаться."
                )
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

    private func purchasedPage(_ item: ShoppingItem?) -> some View {
        NavigationStack {
            ShoppingPage {
                if let item {
                    ShoppingHeading(title: "Покупка отмечена", subtitle: "\(item.name) · \(item.quantity)")
                    purchaseSummary(item)
                        .padding(.top, 46)
                } else {
                    ShoppingHeading(title: "Купленные продукты")
                }

                if let server {
                    ShoppingTransferControls(model: server) { presentation = nil }
                        .padding(.top, 32)
                } else {
                    ShoppingNotice(
                        title: "Готово",
                        message: "Покупка отмечена в списке. Продукты дома можно изменить отдельно."
                    )
                    .padding(.top, 40)
                }

                if let item {
                    Button("Вернуть в список") {
                        if setPurchased(false, id: item.id) != nil { presentation = nil }
                    }
                    .buttonStyle(ShoppingActionStyle(isSecondary: true))
                    .accessibilityHint("Снимает отметку о покупке")
                    .disabled(server?.isSelectionLocked == true)
                    .padding(.top, 50)
                }

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
            .rootScreenHeader(showsDemoLabel: server == nil)
        }
    }

    private func purchaseSummary(_ item: ShoppingItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            purchaseMark(isPurchased: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Куплено")
                    .shoppingFont(14, weight: .medium, lineHeight: 20)
                if let price = item.estimatedPrice {
                    Text(server == nil ? "≈\(shoppingRubles(price)) за упаковку" : shoppingRubles(price))
                        .shoppingFont(12, lineHeight: 17)
                        .foregroundStyle(ShoppingColor.secondary)
                }
            }
        }
        .padding(.vertical, 13)
        .frame(minHeight: 64, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func priceLabel(_ price: Decimal) -> String {
        server == nil ? "≈\(shoppingRubles(price))" : shoppingRubles(price)
    }

    private func setPurchased(_ isPurchased: Bool, id: String) -> ShoppingItem? {
        if let server { return server.setPurchased(isPurchased, id: id) }
        return shopping.setPurchased(isPurchased, id: id)
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

    private func showBudget(_ kind: ShoppingRecommendationKind = .budget) {
        if recommendations == nil, let repository, let server {
            recommendations = ServerShoppingRecommendationModel(repository: repository, shopping: server)
        }
        presentation = .budget(kind)
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
