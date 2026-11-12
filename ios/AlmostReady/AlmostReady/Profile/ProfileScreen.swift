import SwiftUI

struct ProfileScreen: View {
    @Environment(SessionStore.self) private var session: SessionStore?
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
        if let session {
            if let account = session.account {
                ServerProfileScreen(
                    repository: ProfileRepository(session: session, account: account),
                    onOpenProducts: onOpenProducts,
                    onNutritionPresentationChange: onNutritionPresentationChange
                )
                .id(account.id)
            }
        } else {
            DemoProfileScreen(
                onOpenProducts: onOpenProducts,
                onNutritionPresentationChange: onNutritionPresentationChange
            )
        }
    }
}

private struct DemoProfileScreen: View {
    @State private var nutrition = ProfileNutritionEditor()
    let onOpenProducts: (() -> Void)?
    let onNutritionPresentationChange: (Bool) -> Void

    var body: some View {
        ProfileHome(onOpenNutrition: { nutrition.open() }, onOpenProducts: onOpenProducts) {
            ProfileAccountHeader(name: "Алексей", subtitle: "Логин: alex")
                .accessibilityLabel("Демо-профиль, Алексей, логин alex")
        } actions: {
            EmptyView()
        }
        .rootScreenHeader()
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
}

struct ProfileHome<Account: View, Actions: View>: View {
    @Environment(\.floatingTabBarHeight) private var tabBarHeight
    let onOpenNutrition: () -> Void
    let onOpenProducts: (() -> Void)?
    @ViewBuilder let account: Account
    @ViewBuilder let actions: Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RootScreenTitle(tab: .profile)
                    .fixedSize(horizontal: false, vertical: true)

                account
                    .padding(.vertical, 52)

                VStack(spacing: 12) {
                    Button(action: onOpenNutrition) {
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

                    actions
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
        .background(Color(.demoBackground).ignoresSafeArea())
    }
}

struct ProfileAccountHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .title2) private var accountNameSize = 22.0
    @ScaledMetric(relativeTo: .title2) private var avatarLabelSize = 24.0
    let name: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: 20) {
            Text(String(name.prefix(1)).localizedUppercase)
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
                Text(name)
                    .font(.system(size: accountNameSize, weight: .bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Профиль") {
    NavigationStack {
        ProfileScreen()
    }
}
