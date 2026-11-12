import Foundation
import SwiftUI

struct ProfileNutritionScreen: View {
    @Binding var draft: ProfileNutritionSettings
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ProfileForm(title: "Питание и аллергены") {
            ProfileHeading(title: "Предпочтения питания")
            foodTypes
                .padding(.top, 42)
            allergensLink
                .padding(.top, 30)
            restrictions
                .padding(.top, 34)
            dietTableLink
                .padding(.top, 32)
            ProfileNotice(
                title: "Проверяйте сведения",
                message: "Сведения о составе могут быть неполными. Проверяйте состав продуктов."
            )
            .padding(.top, 32)
            VStack(spacing: 4) {
                ProfileSaveButton(title: "Сохранить предпочтения", action: onSave)
                Button(action: onCancel) {
                    Text("Отмена")
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            .padding(.top, 28)
        }
    }

    private var foodTypes: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Тип питания")
                .font(.callout.bold())
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 4) {
                ForEach(ProfileFoodType.allCases, id: \.self) { type in
                    ProfileChoiceRow(title: type.title, isSelected: draft.foodType == type, isSingleChoice: true) {
                        draft.foodType = type
                    }
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
        ProfileForm(title: "Аллергены") {
            ProfileHeading(title: "Что исключить?")
            Text("Выберите нужные аллергены")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(spacing: 6) {
                ForEach(ProfileAllergen.allCases, id: \.self) { allergen in
                    ProfileChoiceRow(title: allergen.title, isSelected: selection.contains(allergen)) {
                        if selection.remove(allergen) == nil { selection.insert(allergen) }
                    }
                }
            }
            .padding(.top, 36)

            ProfileSaveButton(title: "Сохранить выбор") {
                onSave(selection)
                dismiss()
            }
            .padding(.top, 50)

            Text("Чтобы применить выбор, сохраните настройки питания")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            ProfileNotice(
                title: "Сведения могут быть неполными",
                message: "Отсутствие записи об аллергене не подтверждает его отсутствие."
            )
            .padding(.top, 18)
        }
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
        ProfileForm(title: "Диетический стол") {
            ProfileHeading(title: "Диетический стол")

            VStack(alignment: .leading, spacing: 8) {
                Text("Название из назначения")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Название из назначения", text: $name, prompt: Text("Не выбран"), axis: .vertical)
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minHeight: 56)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
            }
            .padding(.top, 68)

            ProfileNotice(
                title: "Соответствие не подтверждено",
                message: "Рецепты пока не проверяются на соответствие диетическому столу."
            )
            .padding(.top, 62)

            Text("Чтобы применить выбор, сохраните настройки питания")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 60, alignment: .topLeading)
                .padding(.top, 32)

            ProfileSaveButton {
                onSave(name.trimmingCharacters(in: .whitespacesAndNewlines))
                dismiss()
            }
            .padding(.top, 42)
        }
    }
}

private struct ProfileForm<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.demoBackground).ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
