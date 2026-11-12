import SwiftUI

struct ProfileScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.floatingTabBarHeight) private var tabBarHeight
    @ScaledMetric(relativeTo: .title2) private var accountNameSize = 22.0
    @ScaledMetric(relativeTo: .title2) private var avatarLabelSize = 24.0
    @State private var nutrition = ProfileNutritionEditor()
    private let onOpenProducts: (() -> Void)?
    private let onNutritionPresentationChange: (Bool) -> Void

    init(
        onOpenProducts: (() -> Void)? = nil,
        onNutritionPresentationChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.onOpenProducts = onOpenProducts
        self.onNutritionPresentationChange = onNutritionPresentationChange
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RootScreenTitle(tab: .profile)
                    .fixedSize(horizontal: false, vertical: true)

                demoAccount
                    .padding(.vertical, 52)

                VStack(spacing: 12) {
                    Button {
                        nutrition.open()
                    } label: {
                        ProfileMenuRow(
                            title: "Питание и аллергены",
                            subtitle: "Предпочтения и предупреждения",
                            icon: "leaf"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile.nutrition")

                    if let onOpenProducts {
                        Button(action: onOpenProducts) {
                            ProfileMenuRow(
                                title: "Мои продукты",
                                subtitle: "Что есть дома",
                                icon: "refrigerator"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.products")
                    }
                }

                Text("Оценки стоимости и КБЖУ могут быть неполными.\nПри ограничениях питания проверяйте состав.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 44)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .safeAreaPadding(.bottom, tabBarHeight)
        .rootScreenHeader()
        .background(Color(.demoBackground).ignoresSafeArea())
        .onChange(of: nutrition.isEditing) { _, isPresented in
            onNutritionPresentationChange(isPresented)
        }
        .navigationDestination(isPresented: nutritionPresentation) {
            ProfileNutritionScreen(
                draft: $nutrition.draft,
                onSave: { nutrition.save() },
                onCancel: { nutrition.cancel() }
            )
            .toolbar(.visible, for: .navigationBar)
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
                .font(.system(size: avatarLabelSize, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .padding(12)
                .frame(minWidth: 64, minHeight: 64)
                .background(
                    colorScheme == .dark
                        ? Color.accentColor.opacity(0.12) : Color(red: 0.980, green: 0.898, blue: 0.863),
                    in: .rect(cornerRadius: 24)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Алексей")
                    .font(.system(size: accountNameSize, weight: .bold))
                Text("Логин: alex")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Демо-профиль, Алексей, логин alex")
    }
}

#Preview("Профиль") {
    NavigationStack {
        ProfileScreen()
    }
}
