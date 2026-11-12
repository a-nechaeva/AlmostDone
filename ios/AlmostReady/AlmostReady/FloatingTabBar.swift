import SwiftUI

enum AppTab: String, CaseIterable {
    case products
    case dishes
    case shopping
    case profile

    var title: LocalizedStringKey {
        switch self {
        case .products: "Продукты"
        case .dishes: "Блюда"
        case .shopping: "Покупки"
        case .profile: "Профиль"
        }
    }

    var icon: ImageResource {
        switch self {
        case .products: .tabFridge
        case .dishes: .tabBowl
        case .shopping: .tabBag
        case .profile: .tabPerson
        }
    }
}

struct FloatingTabBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let selection: AppTab
    var accessibilityNamespace = "tabs"
    let onSelect: (AppTab) -> Void

    var body: some View {
        tabButtons
            .background(surfaceColor, in: .rect(cornerRadius: 28))
            .shadow(color: .black.opacity(0.09), radius: 24, y: 6)
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
    }

    private var surfaceColor: Color {
        colorScheme == .dark ? Color(uiColor: .secondarySystemGroupedBackground) : .white
    }

    private var tabButtons: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(.vertical, 2)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selection == tab

        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 6) {
                Image(tab.icon)
                    .renderingMode(.template)
                    .frame(width: 56, height: 32)
                    .background(isSelected ? selectionBackground : .clear, in: .capsule)
                    .accessibilityHidden(true)
                Text(tab.title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isSelected ? selectedColor : unselectedColor)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tab.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("\(accessibilityNamespace).\(tab.rawValue)")
    }

    private var selectedColor: Color {
        colorScheme == .dark ? .accentColor : Color(red: 155.0 / 255, green: 63.0 / 255, blue: 44.0 / 255)
    }

    private var unselectedColor: Color {
        colorScheme == .dark ? .secondary : Color(red: 108.0 / 255, green: 107.0 / 255, blue: 102.0 / 255)
    }

    private var selectionBackground: Color {
        colorScheme == .dark
            ? Color.accentColor.opacity(0.16)
            : Color(red: 250.0 / 255, green: 229.0 / 255, blue: 220.0 / 255)
    }
}

extension View {
    func floatingTabBarInset<Bar: View>(@ViewBuilder content: () -> Bar) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0, content: content)
    }
}
