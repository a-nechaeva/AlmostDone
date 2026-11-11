import SwiftUI
import UIKit

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
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ShoppingActionStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var isSecondary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .multilineTextAlignment(.center)
            .foregroundStyle(isSecondary ? Color.accentColor : colorScheme == .dark ? .black : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                Color.accentColor.opacity(isSecondary ? 0.14 : 1),
                in: .rect(cornerRadius: 16)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct ShoppingNotice: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var isWarning = false

    private var tint: Color {
        if isWarning {
            return colorScheme == .dark
                ? Color(red: 1, green: 0.78, blue: 0.43)
                : Color(red: 0.49, green: 0.31, blue: 0.08)
        }
        return colorScheme == .dark
            ? Color(red: 0.60, green: 0.82, blue: 0.68)
            : Color(red: 0.20, green: 0.41, blue: 0.29)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle")
                .font(.headline)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline.bold())
                Text(message)
                    .font(.subheadline)
            }
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .frame(minHeight: 100)
        .background(tint.opacity(0.10), in: .rect(cornerRadius: 20))
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
                .foregroundStyle(Color.accentColor)
                .frame(width: 88, height: 88)
                .background(Color.accentColor.opacity(0.14), in: .rect(cornerRadius: 28))
                .accessibilityHidden(true)

            Text(title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 28)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 310)
                .padding(.top, 16)

            Button(buttonTitle, action: action)
                .buttonStyle(ShoppingActionStyle())
                .padding(.top, 36)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

extension View {
    func shoppingCard(cornerRadius: CGFloat = 20) -> some View {
        background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: cornerRadius))
    }
}
