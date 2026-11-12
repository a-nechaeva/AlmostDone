import SwiftUI

extension EnvironmentValues {
    @Entry var floatingTabBarHeight: CGFloat = 0
}

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
    private struct TabButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            // The selection capsule provides feedback without dimming the icon.
            configuration.label
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    let selection: AppTab
    var accessibilityNamespace = "tabs"
    let onSelect: (AppTab) -> Void

    private let iconHeight: CGFloat = 32

    var body: some View {
        tabButtons
            .background {
                surface
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private var surface: some View {
        let shape = Capsule()
        if #available(iOS 26.0, *), !reduceTransparency {
            Color.clear
                .glassEffect(.clear, in: shape)
                .background {
                    shape
                        .fill(Color(.demoBackground).opacity(colorScheme == .dark ? 0.26 : 0.18))
                        .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
                }
                .overlay {
                    shape.strokeBorder(glassRim, lineWidth: 1)
                        .allowsHitTesting(false)
                }
        } else {
            shape
                .fill(surfaceColor)
                .shadow(color: .black.opacity(0.09), radius: 24, y: 6)
        }
    }

    private var surfaceColor: Color {
        colorScheme == .dark ? Color(uiColor: .secondarySystemGroupedBackground) : .white
    }

    private var glassRim: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(colorScheme == .dark ? 0.48 : 0.95),
                .white.opacity(0.10),
                colorScheme == .dark ? .white.opacity(0.18) : .black.opacity(0.14)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var tabButtons: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .background { selectionCapsule }
        .padding(.vertical, 2)
    }

    private var selectionCapsule: some View {
        GeometryReader { geometry in
            let tabs = AppTab.allCases
            let slotWidth = geometry.size.width / CGFloat(tabs.count)
            let index = tabs.firstIndex(of: selection) ?? 0
            let column = layoutDirection == .rightToLeft ? tabs.count - 1 - index : index

            Capsule()
                .fill(selectionBackground)
                .frame(width: min(56, slotWidth), height: iconHeight)
                .position(x: (CGFloat(column) + 0.5) * slotWidth, y: geometry.size.height / 2)
                .animation(reduceMotion ? nil : .spring(duration: 0.32, bounce: 0), value: selection)
        }
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selection == tab

        return Button {
            onSelect(tab)
        } label: {
            Image(tab.icon)
                .renderingMode(.template)
                .foregroundStyle(isSelected ? selectedColor : Color.primary)
                .animation(nil, value: isSelected)
                .frame(height: iconHeight)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(TabButtonStyle())
        .accessibilityLabel(Text(tab.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("\(accessibilityNamespace).\(tab.rawValue)")
    }

    private var selectedColor: Color {
        colorScheme == .dark ? .accentColor : Color(red: 155.0 / 255, green: 63.0 / 255, blue: 44.0 / 255)
    }

    private var selectionBackground: Color {
        selectedColor.opacity(0.16)
    }
}
