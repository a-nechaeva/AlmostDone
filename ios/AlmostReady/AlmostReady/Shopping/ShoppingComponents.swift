import SwiftUI
import UIKit

enum ShoppingColor {
    static let accent = adaptive(light: 0x9B3F2C, dark: 0xFFA385)
    static let action = adaptive(light: 0xB64C35, dark: 0xFFA385)
    static let accentSurface = adaptive(light: 0xFAE5DC, dark: 0x4B2D24)
    static let secondary = adaptive(light: 0x6C6B66, dark: 0xBDB8AE)
    static let outline = adaptive(light: 0x7D8178, dark: 0xA8A69C)
    static let warning = adaptive(light: 0x855A18, dark: 0xFFC76E)
    static let warningSurface = adaptive(light: 0xFAEED7, dark: 0x423422)
    static let success = adaptive(light: 0x34694B, dark: 0x99D1AD)
    static let successSurface = adaptive(light: 0xE7F1E8, dark: 0x26392C)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(
            uiColor: UIColor { traits in
                let rgb = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(
                    red: CGFloat((rgb >> 16) & 0xFF) / 255,
                    green: CGFloat((rgb >> 8) & 0xFF) / 255,
                    blue: CGFloat(rgb & 0xFF) / 255,
                    alpha: 1
                )
            }
        )
    }
}

struct ShoppingPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.demoBackground).ignoresSafeArea())
    }
}

struct ShoppingHeading: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .shoppingFont(30, weight: .bold, lineHeight: 36)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .shoppingFont(14, lineHeight: 20)
                    .foregroundStyle(ShoppingColor.secondary)
            }
        }
    }
}

struct ShoppingActionStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var isSecondary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .shoppingFont(14, weight: .bold, lineHeight: 19)
            .multilineTextAlignment(.center)
            .foregroundStyle(isSecondary ? ShoppingColor.accent : colorScheme == .dark ? .black : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                isSecondary ? ShoppingColor.accentSurface : ShoppingColor.action,
                in: .rect(cornerRadius: 16)
            )
            .contentShape(.rect(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct ShoppingNotice: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var isWarning = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 18))
                .frame(width: 22, height: 22)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .shoppingFont(14, weight: .bold, lineHeight: 20)
                Text(message)
                    .lineSpacing(3)
                    .shoppingFont(13, lineHeight: 19)
            }
        }
        .foregroundStyle(isWarning ? ShoppingColor.warning : ShoppingColor.success)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .frame(minHeight: 100, alignment: .topLeading)
        .background(
            isWarning ? ShoppingColor.warningSurface : ShoppingColor.successSurface,
            in: .rect(cornerRadius: 20)
        )
        .accessibilityElement(children: .combine)
    }
}

struct ShoppingEmptyState: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let buttonTitle: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "bag")
                .font(.system(size: 30))
                .foregroundStyle(ShoppingColor.accent)
                .frame(width: 88, height: 88)
                .background(ShoppingColor.accentSurface, in: .rect(cornerRadius: 28))
                .accessibilityHidden(true)

            Text(title)
                .shoppingFont(24, weight: .bold, lineHeight: 34)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 28)

            Text(message)
                .lineSpacing(4)
                .shoppingFont(14, lineHeight: 21)
                .foregroundStyle(ShoppingColor.secondary)
                .frame(maxWidth: 310)
                .padding(.top, 18)

            Button(buttonTitle, action: action)
                .buttonStyle(ShoppingActionStyle())
                .padding(.top, 38)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

private struct ShoppingFont: ViewModifier {
    @ScaledMetric private var scale: CGFloat = 1
    let size: CGFloat
    let weight: Font.Weight
    let lineHeight: CGFloat

    func body(content: Content) -> some View {
        content
            .font(.system(size: size * scale, weight: weight))
            .frame(minHeight: lineHeight * scale)
    }
}

extension View {
    func shoppingFont(_ size: CGFloat, weight: Font.Weight = .regular, lineHeight: CGFloat) -> some View {
        modifier(ShoppingFont(size: size, weight: weight, lineHeight: lineHeight))
    }

    func shoppingCard(cornerRadius: CGFloat) -> some View {
        background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: cornerRadius))
    }
}
