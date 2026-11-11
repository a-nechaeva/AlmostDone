import SwiftUI

struct ProfileScreen: View {
    @State private var nutrition = ProfileNutritionEditor()
    private let onOpenProducts: (() -> Void)?

    init(onOpenProducts: (() -> Void)? = nil) {
        self.onOpenProducts = onOpenProducts
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                demoAccount
                    .padding(.vertical, 24)

                Button {
                    nutrition.open()
                } label: {
                    ProfileMenuRow(
                        title: "Питание и аллергены",
                        subtitle: "Предпочтения и ограничения",
                        icon: "leaf"
                    )
                }
                .buttonStyle(.plain)

                if let onOpenProducts {
                    Button(action: onOpenProducts) {
                        ProfileMenuRow(
                            title: "Мои продукты",
                            subtitle: "Что есть дома",
                            icon: "refrigerator"
                        )
                    }
                    .buttonStyle(.plain)
                }

                Text("Оценки стоимости и КБЖУ могут быть неполными.\nПри ограничениях питания проверяйте состав.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 24)
            }
            .padding(20)
        }
        .background(Color(.demoBackground))
        .navigationTitle("Профиль")
        .navigationDestination(isPresented: nutritionPresentation) {
            ProfileNutritionScreen(
                draft: $nutrition.draft,
                onSave: { nutrition.save() },
                onCancel: { nutrition.cancel() }
            )
        }
    }

    private var nutritionPresentation: Binding<Bool> {
        Binding(
            get: { nutrition.isEditing },
            set: { isPresented in
                // System Back clears the same draft as the explicit cancel button.
                if !isPresented { nutrition.cancel() }
            }
        )
    }

    private var demoAccount: some View {
        HStack(spacing: 20) {
            Text("А")
                .font(.title2.bold())
                .foregroundStyle(Color.accentColor)
                .frame(width: 64, height: 64)
                .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 24))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Демо-профиль")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Алексей")
                    .font(.title2.bold())
                Text("Логин: alex")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Профиль") {
    NavigationStack {
        ProfileScreen()
    }
}
