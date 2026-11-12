import SwiftUI

struct PantryEditor: View {
    @Bindable var draft: PantryDraft
    let model: PantryModel
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Количество", text: $draft.quantityText)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("products.quantity")
                    if !draft.allowedUnits.isEmpty {
                        Picker("Единица", selection: $draft.unit) {
                            Text("Выберите единицу").tag(nil as PantryUnit?)
                            ForEach(draft.allowedUnits, id: \.self) { unit in
                                Text(unit.label).tag(Optional(unit))
                            }
                        }
                    }
                } footer: {
                    Text("Оставьте поле пустым, если количество неизвестно")
                    if draft.hasInvalidAmount {
                        Text(
                            draft.isAdding
                                ? "Укажите количество больше нуля и не больше 1 000 000"
                                : "Укажите количество от 0 до 1 000 000"
                        )
                    } else if !draft.isAdding {
                        Text("Ноль удалит продукт из запасов")
                    }
                }
                .disabled(draft.hasPendingAdd || model.isSaving)

                if draft.isLoadingCatalog {
                    ProgressView("Загружаем единицы измерения")
                } else if draft.catalogLoadFailed {
                    Text("Не удалось загрузить единицы измерения")
                    Button("Повторить") { Task { await draft.loadUnits(from: model.repository) } }
                }

                feedback

                if model.isSaving {
                    ProgressView("Обновляем запасы")
                }

                if !draft.isAdding {
                    Button("Удалить продукт", role: .destructive) { save(deleting: true) }
                        .disabled(model.isSaving || model.isLoading || draft.issue == .refreshFailed)
                        .accessibilityIdentifier("products.remove.\(draft.ingredientID)")
                }
            }
            .navigationTitle(draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(draft.hasPendingAdd ? "Закрыть" : "Отмена", action: onClose)
                        .disabled(model.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) { save() }
                        .disabled(!draft.canSave || model.isSaving || model.isLoading || draft.issue == .refreshFailed)
                        .accessibilityIdentifier("products.save")
                }
            }
            .task { await draft.loadUnits(from: model.repository) }
        }
        .interactiveDismissDisabled(model.isSaving)
    }

    @ViewBuilder
    private var feedback: some View {
        switch draft.issue {
        case .conflict:
            Text("Запасы изменились. Проверьте количество перед сохранением.")
            if let item = draft.currentItem {
                LabeledContent("Сейчас в запасах", value: item.quantity?.label ?? "Количество не указано")
            } else {
                Text("Сейчас этого продукта нет в запасах")
            }
        case .refreshFailed:
            Text("Запасы изменились. Не удалось загрузить новый список.")
            Button("Обновить запасы") { Task { await model.retryRebase(draft) } }
                .disabled(model.isSaving || model.isLoading)
        case .unitConflict:
            Text("Сервер не смог сложить количества в этих единицах. Проверьте единицу измерения.")
        case .uncertainAdd:
            Text("Сервер не подтвердил добавление. Повторите тот же запрос.")
        case .saveFailed:
            Text("Не удалось сохранить изменение. Попробуйте ещё раз.")
        case nil:
            EmptyView()
        }
    }

    private var saveTitle: LocalizedStringKey {
        if draft.hasPendingAdd { return "Повторить" }
        return draft.isAdding ? "Добавить" : "Сохранить"
    }

    private func save(deleting: Bool = false) {
        Task {
            if await model.save(draft, deleting: deleting) {
                onClose()
            }
        }
    }
}
