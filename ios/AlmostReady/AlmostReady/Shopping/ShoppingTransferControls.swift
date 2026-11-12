import SwiftUI

struct ShoppingTransferControls: View {
    let model: ServerShoppingModel
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Перенести в запасы")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(model.items.filter(\.isPurchased)) { item in
                Text("\(item.name) · \(item.quantity)")
            }

            if let feedback {
                Text(feedback)
                    .font(.footnote)
                    .foregroundStyle(ShoppingColor.secondary)
                    .accessibilityIdentifier("shopping.transfer.status")
            }

            Button(buttonTitle) {
                Task { await model.confirmTransfer() }
            }
            .buttonStyle(ShoppingActionStyle())
            .disabled(model.transferState == .transferring)
            .accessibilityIdentifier("shopping.transfer.confirm")

            if model.transferState == .needsConfirmation || model.transferState == .revisionUnavailable {
                Button("Изменить выбор") {
                    model.cancelReconciledTransfer()
                    onComplete()
                }
                .buttonStyle(ShoppingActionStyle(isSecondary: true))
            }
        }
        .onChange(of: model.transferState) { _, state in
            if state == .completed { onComplete() }
        }
    }

    private var buttonTitle: LocalizedStringKey {
        switch model.transferState {
        case .transferring: "Обновляем запасы…"
        case .retry, .revisionUnavailable: "Повторить"
        default: "Подтвердить перенос"
        }
    }

    private var feedback: LocalizedStringKey? {
        switch model.transferState {
        case .needsConfirmation:
            "Запасы изменились. Проверьте выбранные позиции и подтвердите перенос ещё раз."
        case .revisionUnavailable:
            "Не удалось проверить текущую версию запасов. Выбранные позиции сохранены."
        case .retry:
            "Не удалось подтвердить перенос. Повторите эту же операцию."
        case .invalidSelection:
            "Не удалось объединить выбранные количества. Проверьте отметки в списке покупок."
        case .rejected:
            "Сервер отклонил перенос. Проверьте выбранные позиции и продукты дома."
        default:
            nil
        }
    }
}
