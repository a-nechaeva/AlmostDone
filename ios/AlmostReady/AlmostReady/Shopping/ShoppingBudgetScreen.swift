import Accessibility
import Foundation
import SwiftUI

struct ShoppingBudgetScreen: View {
    private enum ScrollTarget {
        case budgetField
    }

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditingBudget: Bool
    @State private var error: ShoppingBudgetError?
    @State private var result: ShoppingBudgetResult?
    @Binding var input: String
    let hasDemoPlan: Bool
    let onFinishPlan: () -> Void

    var body: some View {
        ScrollViewReader { scroll in
            let submitBudget = { submit(scroll: scroll) }
            ShoppingPage {
                ShoppingHeading(title: "Сколько потратим?", subtitle: "Покажем пример покупок на ваш бюджет")
                budgetField(onSubmit: submitBudget)
                    .padding(.top, 46)
                presets
                    .padding(.top, 36)
                ShoppingNotice(
                    title: "Примерные цены",
                    message: "Показываем стоимость упаковок. Фактическая сумма зависит от магазина.",
                    isWarning: true
                )
                .padding(.top, 36)

                Button("Подобрать план", action: submitBudget)
                    .buttonStyle(ShoppingActionStyle())
                    .padding(.top, 56)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("План покупок")
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
    }

    private func budgetField(onSubmit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Бюджет, ₽")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Бюджет, ₽", text: $input, prompt: Text("Введите сумму"))
                .keyboardType(.decimalPad)
                .focused($isEditingBudget)
                .onSubmit(onSubmit)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: 56)
                .shoppingCard(cornerRadius: 16)
                .accessibilityIdentifier("shopping.budget.input")

            if let error {
                Text(errorMessage(error))
                    .font(.footnote)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("shopping.budget.error")
            }
        }
        .id(ScrollTarget.budgetField)
    }

    private var presets: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                presetButtons
            }
            VStack(alignment: .leading, spacing: 4) {
                presetButtons
            }
        }
    }

    private var presetButtons: some View {
        ForEach([200, 500, 1_000], id: \.self) { amount in
            let isSelected = input == String(amount)
            Button {
                input = String(amount)
                isEditingBudget = false
            } label: {
                Text(shoppingRubles(Decimal(amount)))
                    .font(.footnote.weight(isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(
                        isSelected ? Color.accentColor.opacity(0.14) : Color(.secondarySystemGroupedBackground),
                        in: .capsule
                    )
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    private func submit(scroll: ScrollViewProxy) {
        switch ShoppingBudgetResult.evaluate(input) {
        case .success(let evaluation):
            error = nil
            isEditingBudget = false
            result = evaluation
        case .failure(let validationError):
            error = validationError
            scroll.scrollTo(ScrollTarget.budgetField, anchor: .top)
            AccessibilityNotification.Announcement(String(localized: errorMessage(validationError))).post()
        }
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
                .padding(.top, 100)
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
                title: "Демоплан · ≈\(price) · ещё два блюда",
                message: "Останется примерно \(remainder)."
            )
            .padding(.top, 38)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(ShoppingDemoPlan.cheese.name) · \(ShoppingDemoPlan.cheese.quantity)")
                        .font(.subheadline.weight(.medium))
                    Text("≈\(price) за упаковку")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .shoppingCard()
            .accessibilityElement(children: .combine)
            .padding(.top, 28)

            Text("Что станет доступно")
                .font(.headline.bold())
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
                .padding(.top, 48)
            Text("Блюда — отдельные варианты приготовления.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 24)
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
                .clipShape(.rect(cornerRadius: 20))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.bold())
                Text(details)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Нужен сыр · ≈\(price) докупить")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .shoppingCard(cornerRadius: 24)
        .accessibilityElement(children: .combine)
    }
}
