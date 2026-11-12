import Accessibility
import Foundation
import SwiftUI

struct ShoppingBudgetScreen: View {
    private enum ScrollTarget {
        case budgetField
        case serverResults
    }

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditingBudget: Bool
    @State private var error: ShoppingBudgetError?
    @State private var result: ShoppingBudgetResult?
    @Binding var input: String
    let hasDemoPlan: Bool
    var server: ServerShoppingModel? = nil
    var kind: ShoppingRecommendationKind = .budget
    let onFinishPlan: () -> Void

    var body: some View {
        ScrollViewReader { scroll in
            let submitBudget = { submit(scroll: scroll) }
            ShoppingPage {
                if server == nil {
                    ShoppingHeading(title: "Сколько потратим?", subtitle: "Покажем пример покупок на ваш бюджет")
                } else {
                    ShoppingHeading(title: kind == .budget ? "Сколько потратим?" : "Одиночная покупка")
                }
                budgetField(onSubmit: submitBudget)
                    .padding(.top, 48)
                presets
                    .padding(.top, 40)
                if let server {
                    Stepper(
                        "Порций: \(server.servings)",
                        value: Binding(get: { server.servings }, set: { server.servings = $0 }),
                        in: 1...12
                    )
                    .padding(.top, 24)
                }
                ShoppingNotice(
                    title: "Примерные цены",
                    message: "Показываем стоимость упаковок. Фактическая сумма зависит от магазина.",
                    isWarning: true
                )
                .padding(.top, 38)

                if !showsRetry {
                    Button(submitTitle, action: submitBudget)
                        .buttonStyle(ShoppingActionStyle())
                        .disabled(isLoading)
                        .padding(.top, 60)
                }

                if let server {
                    ShoppingServerResults(
                        model: server, kind: kind, onAdd: onFinishPlan, onRetry: submitBudget
                    )
                    .padding(.top, 24)
                    .id(ScrollTarget.serverResults)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(kind == .budget ? "План покупок" : "Одиночная покупка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Label("К списку покупок", systemImage: "arrow.left")
                }
                .labelStyle(.iconOnly)
            }
        }
        .navigationDestination(item: $result) { result in
            ShoppingBudgetResultScreen(
                result: result,
                hasDemoPlan: hasDemoPlan,
                onFinishPlan: onFinishPlan
            )
        }
        .onChange(of: input) { _, _ in error = nil }
        .onChange(of: server?.revision) { _, _ in server?.discardRecommendation() }
        .onDisappear { server?.discardRecommendation() }
    }

    private func budgetField(onSubmit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Бюджет, ₽")
                .shoppingFont(13, weight: .medium, lineHeight: 18)
                .foregroundStyle(ShoppingColor.secondary)
                .accessibilityHidden(true)
            TextField("Бюджет, ₽", text: $input, prompt: Text("Введите сумму"))
                .keyboardType(.decimalPad)
                .focused($isEditingBudget)
                .onSubmit(onSubmit)
                .shoppingFont(16, lineHeight: 22)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: 56)
                .shoppingCard(cornerRadius: 16)
                .accessibilityIdentifier("shopping.budget.input")

            if let validationError {
                Text(errorMessage(validationError))
                    .font(.footnote)
                    .foregroundStyle(ShoppingColor.accent)
                    .accessibilityIdentifier("shopping.budget.error")
            }
        }
        .id(ScrollTarget.budgetField)
    }

    private var presets: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                preset(200, preferredWidth: 104)
                preset(500, preferredWidth: 104)
                preset(1_000)
            }
            VStack(alignment: .leading, spacing: 4) {
                preset(200)
                preset(500)
                preset(1_000)
            }
        }
    }

    private func preset(_ amount: Int, preferredWidth: CGFloat? = nil) -> some View {
        let isSelected = input == String(amount)
        return Button {
            input = String(amount)
            isEditingBudget = false
        } label: {
            Text(shoppingRubles(Decimal(amount)))
                .shoppingFont(13, weight: isSelected ? .bold : .medium, lineHeight: 18)
                .foregroundStyle(isSelected ? ShoppingColor.accent : ShoppingColor.secondary)
                .fixedSize()
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(minWidth: preferredWidth, maxWidth: .infinity, minHeight: 36)
                .fixedSize(horizontal: preferredWidth != nil, vertical: false)
                .background(
                    isSelected ? ShoppingColor.accentSurface : Color(.secondarySystemGroupedBackground),
                    in: .capsule
                )
                .frame(minHeight: 48)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var validationError: ShoppingBudgetError? {
        if let server, case .invalidBudget(let error) = server.recommendation { return error }
        return error
    }

    private var isLoading: Bool {
        guard let server, case .loading = server.recommendation else { return false }
        return true
    }

    private var showsRetry: Bool {
        guard let server, case .unavailable = server.recommendation else { return false }
        return true
    }

    private var submitTitle: LocalizedStringKey {
        kind == .budget ? "Подобрать план" : "Подобрать покупку"
    }

    private func submit(scroll: ScrollViewProxy) {
        if let server {
            Task {
                guard let id = await server.loadRecommendation(kind), server.isCurrentRecommendation(id) else { return }
                switch server.recommendation {
                case .invalidBudget(let error):
                    showBudgetError(error, scroll: scroll)
                case .result, .unavailable:
                    isEditingBudget = false
                    scroll.scrollTo(ScrollTarget.serverResults, anchor: .top)
                default:
                    break
                }
            }
            return
        }
        switch ShoppingBudgetResult.evaluate(input) {
        case .success(let evaluation):
            error = nil
            isEditingBudget = false
            result = evaluation
        case .failure(let validationError):
            error = validationError
            showBudgetError(validationError, scroll: scroll)
        }
    }

    private func showBudgetError(_ error: ShoppingBudgetError, scroll: ScrollViewProxy) {
        scroll.scrollTo(ScrollTarget.budgetField, anchor: .top)
        AccessibilityNotification.Announcement(String(localized: errorMessage(error))).post()
    }

    private func errorMessage(_ error: ShoppingBudgetError) -> LocalizedStringResource {
        switch error {
        case .empty: "Введите сумму в рублях."
        case .zero: "Введите сумму больше нуля."
        case .invalid: "Введите сумму в рублях, например 250 или 250,50."
        }
    }
}

private struct ShoppingBudgetResultScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let result: ShoppingBudgetResult
    let hasDemoPlan: Bool
    let onFinishPlan: () -> Void

    var body: some View {
        ShoppingPage {
            switch result {
            case .example(let budget):
                examplePlan(budget: budget)
            case .unavailable(let budget):
                ShoppingHeading(title: "Бюджет \(shoppingRubles(budget))")
                ShoppingEmptyState(
                    title: "Пока нет подходящего плана",
                    message:
                        "Покупка из демоплана стоит около \(shoppingRubles(ShoppingDemoPlan.price)). Увеличьте бюджет.",
                    buttonTitle: "Изменить бюджет"
                ) {
                    dismiss()
                }
                .padding(.top, 116)
            }
        }
        .navigationTitle("План покупок")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func examplePlan(budget: Decimal) -> some View {
        let price = shoppingRubles(ShoppingDemoPlan.price)
        let remainder = shoppingRubles(budget - ShoppingDemoPlan.price)

        return VStack(alignment: .leading, spacing: 0) {
            ShoppingHeading(title: "В пределах бюджета", subtitle: "Бюджет \(shoppingRubles(budget))")
            ShoppingNotice(
                title: "Демоплан · ≈\(price) → ещё 2 блюда",
                message: "Останется примерно \(remainder)"
            )
            .padding(.top, 40)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(ShoppingDemoPlan.cheese.name) · \(ShoppingDemoPlan.packageWeight)")
                        .shoppingFont(15, weight: .medium, lineHeight: 21)
                    Text("≈\(price) за упаковку")
                        .shoppingFont(12, lineHeight: 17)
                        .foregroundStyle(ShoppingColor.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ShoppingColor.secondary)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .shoppingCard(cornerRadius: 18)
            .accessibilityElement(children: .combine)
            .padding(.top, 28)

            Text("Что станет доступно")
                .shoppingFont(18, weight: .bold, lineHeight: 25)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 36)
                .padding(.bottom, 16)

            VStack(spacing: 12) {
                dish(
                    "Паста с томатами и сыром",
                    details: "20 мин · 549 ккал",
                    photo: Image(.dishesTomatoCheesePasta),
                    price: price
                )
                dish(
                    "Омлет с сыром",
                    details: "15 мин · 443 ккал",
                    photo: Image(.dishesTomatoOmelet),
                    price: price
                )
            }

            Button(hasDemoPlan ? "К списку покупок" : "Добавить план в покупки", action: onFinishPlan)
                .buttonStyle(ShoppingActionStyle())
                .padding(.top, 52)
            Text("Блюда — отдельные варианты приготовления.")
                .shoppingFont(12, lineHeight: 17)
                .foregroundStyle(ShoppingColor.secondary)
                .padding(.top, 30)
        }
    }

    private func dish(_ title: LocalizedStringKey, details: LocalizedStringKey, photo: Image, price: String)
        -> some View
    {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))

        return layout {
            photo
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100)
                .clipShape(.rect(cornerRadius: 22))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .lineSpacing(2)
                    .shoppingFont(18, weight: .bold, lineHeight: 24)
                Text(details)
                    .shoppingFont(13, lineHeight: 18)
                    .foregroundStyle(ShoppingColor.secondary)
                Text("Нужен сыр · ≈\(price) докупить")
                    .shoppingFont(12, weight: .medium, lineHeight: 16)
                    .foregroundStyle(ShoppingColor.accent)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .shoppingCard(cornerRadius: 24)
        .accessibilityElement(children: .combine)
    }
}
