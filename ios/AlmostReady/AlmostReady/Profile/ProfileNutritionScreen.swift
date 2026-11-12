import Foundation
import SwiftUI

struct ProfileNutritionScreen: View {
    @Binding var draft: ProfileNutritionSettings
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Предпочтения питания")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                foodTypes
                allergensLink
                restrictions
                dietTableLink
                ProfileNotice(
                    title: "Проверяйте сведения",
                    message: "Сведения о составе могут быть неполными."
                )
                VStack(spacing: 4) {
                    ProfileSaveButton(action: onSave)
                    Button(action: onCancel) {
                        Text("Отмена")
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.demoBackground))
        .navigationTitle("Питание и аллергены")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var foodTypes: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Тип питания")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(ProfileFoodType.allCases, id: \.self) { type in
                ProfileChoiceRow(title: type.title, isSelected: draft.foodType == type, isSingleChoice: true) {
                    draft.foodType = type
                }
            }
        }
    }

    private var allergensLink: some View {
        let selected = ProfileAllergen.allCases.filter { draft.allergens.contains($0) }
        return NavigationLink {
            ProfileAllergensScreen(selection: draft.allergens) { draft.allergens = $0 }
        } label: {
            ProfileMenuRow(
                title: "Аллергены",
                subtitle: selected.isEmpty ? "Не выбраны" : selected.map(\.title).joined(separator: ", ")
            )
        }
        .buttonStyle(.plain)
    }

    private var restrictions: some View {
        VStack(spacing: 4) {
            ProfileChoiceRow(title: "Без глютена", isSelected: draft.isGlutenFree) {
                draft.isGlutenFree.toggle()
            }
            ProfileChoiceRow(title: "Без лактозы", isSelected: draft.isLactoseFree) {
                draft.isLactoseFree.toggle()
            }
            ProfileChoiceRow(title: "Диабет", isSelected: draft.hasDiabetes) {
                draft.hasDiabetes.toggle()
            }
        }
    }

    private var dietTableLink: some View {
        NavigationLink {
            ProfileDietTableScreen(name: draft.dietTableName) { draft.dietTableName = $0 }
        } label: {
            ProfileMenuRow(
                title: "Диетический стол",
                subtitle: draft.dietTableName.isEmpty ? "Не выбран" : draft.dietTableName
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileAllergensScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<ProfileAllergen>
    private let onSave: (Set<ProfileAllergen>) -> Void

    init(selection: Set<ProfileAllergen>, onSave: @escaping (Set<ProfileAllergen>) -> Void) {
        _selection = State(initialValue: selection)
        self.onSave = onSave
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Что исключить?")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Выберите нужные аллергены")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    ForEach(ProfileAllergen.allCases, id: \.self) { allergen in
                        ProfileChoiceRow(title: allergen.title, isSelected: selection.contains(allergen)) {
                            if selection.remove(allergen) == nil { selection.insert(allergen) }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ProfileSaveButton(title: "Сохранить выбор") {
                        onSave(selection)
                        dismiss()
                    }
                    Text("Чтобы применить выбор, сохраните настройки питания")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ProfileNotice(
                    title: "Сведения могут быть неполными",
                    message: "Отсутствие записи об аллергене не подтверждает его отсутствие."
                )
            }
            .padding(20)
        }
        .background(Color(.demoBackground))
        .navigationTitle("Аллергены")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProfileDietTableScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    private let onSave: (String) -> Void

    init(name: String, onSave: @escaping (String) -> Void) {
        _name = State(initialValue: name)
        self.onSave = onSave
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Диетический стол")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Название из назначения")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("Название из назначения", text: $name, prompt: Text("Не выбран"))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 56)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                }

                ProfileNotice(
                    title: "Соответствие не подтверждено",
                    message: "Рецепты пока не проверяются на соответствие диетическому столу."
                )
                Text("Чтобы применить выбор, сохраните настройки питания")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProfileSaveButton {
                    onSave(name.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.demoBackground))
        .navigationTitle("Диетический стол")
        .navigationBarTitleDisplayMode(.inline)
    }
}
