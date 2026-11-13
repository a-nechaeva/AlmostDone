import SwiftUI

struct ServerDishesFiltersSheet: View {
    private enum AllergenCatalog {
        case loading
        case loaded([ProfileAllergenOption])
        case failed
    }

    @Environment(\.dismiss) private var dismiss
    @State private var minutes: String
    @State private var kcal: String
    @State private var draft: DishesAdvancedFilters
    @State private var allergens = AllergenCatalog.loading
    @State private var catalogAttempt = 0

    let repository: RecommendationsRepository
    let applied: DishesAdvancedFilters
    private let numbers: DishesFilterNumbers
    let onApply: (DishesAdvancedFilters) -> Void

    init(
        repository: RecommendationsRepository, applied: DishesAdvancedFilters, locale: Locale,
        onApply: @escaping (DishesAdvancedFilters) -> Void
    ) {
        self.repository = repository
        self.applied = applied
        self.onApply = onApply
        _draft = State(initialValue: applied)
        _minutes = State(initialValue: applied.maxMinutes.map(String.init) ?? "")
        let numbers = DishesFilterNumbers(locale: locale)
        self.numbers = numbers
        _kcal = State(initialValue: numbers.kcalText(applied.maxKcalPerServing))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Лимиты") {
                    TextField("Максимум минут", text: $minutes)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("dishes.filters.minutes")
                    TextField("Максимум ккал на порцию", text: $kcal)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("dishes.filters.kcal")
                    if validated == nil {
                        Text("Укажите целое время от 1 минуты и калорийность от 0 ккал.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Доступное оборудование") {
                    ForEach(DishesAdvancedFilters.Equipment.allCases) { equipment in
                        Toggle(equipment.title, isOn: membership(equipment, in: $draft.equipment))
                    }
                }

                Section {
                    allergenOptions
                } header: {
                    Text("Исключить аллергены")
                } footer: {
                    Text("Исключения действуют только в этом подборе.")
                }

                Button("Сбросить фильтры") {
                    minutes = ""
                    kcal = ""
                    draft = DishesAdvancedFilters()
                }
            }
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Применить") {
                        guard let validated else { return }
                        onApply(validated)
                        dismiss()
                    }
                    .disabled(validated == nil || validated == applied)
                }
            }
            .task(id: catalogAttempt) { await loadAllergens() }
        }
    }

    @ViewBuilder
    private var allergenOptions: some View {
        switch allergens {
        case .loading:
            ProgressView("Загружаем аллергены…")
        case .loaded(let options):
            if options.isEmpty {
                Text("В справочнике нет аллергенов")
                    .foregroundStyle(.secondary)
            }
            ForEach(options) { allergen in
                if allergen.support == .supported || draft.excludedAllergenIDs.contains(allergen.id) {
                    Toggle(allergen.name, isOn: membership(allergen.id, in: $draft.excludedAllergenIDs))
                } else {
                    Text(allergen.name)
                        .foregroundStyle(.secondary)
                }
            }
        case .failed:
            Text("Не удалось загрузить аллергены")
                .foregroundStyle(.secondary)
            Button("Повторить") { catalogAttempt += 1 }
        }
    }

    private var validated: DishesAdvancedFilters? {
        numbers.applying(minutes: minutes, kcal: kcal, to: draft)
    }

    private func loadAllergens() async {
        allergens = .loading
        do {
            let options = try await repository.allergens()
            guard !Task.isCancelled, repository.session.isCurrent(repository.account) else { return }
            allergens = .loaded(options)
        } catch {
            guard !Task.isCancelled else { return }
            allergens = .failed
        }
    }

    private func membership<Element: Hashable>(_ element: Element, in selection: Binding<Set<Element>>) -> Binding<Bool>
    {
        Binding {
            selection.wrappedValue.contains(element)
        } set: { selected in
            if selected {
                selection.wrappedValue.insert(element)
            } else {
                selection.wrappedValue.remove(element)
            }
        }
    }
}
