import SwiftUI

private struct RootScreenHeader: View {
    @ScaledMetric(relativeTo: .title3) private var logoSize = 26.0

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                wordmark
                Spacer(minLength: 0)
                demoLabel
            }

            VStack(alignment: .leading, spacing: 4) {
                wordmark
                demoLabel
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .background(Color(.demoBackground), ignoresSafeAreaEdges: .top)
    }

    private var wordmark: some View {
        HStack(spacing: 12) {
            Image(.tabBowl)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.accentColor)
                .frame(width: logoSize, height: logoSize)
                .accessibilityHidden(true)
            Text("почти готово")
                .font(.title3.bold())
                .accessibilityIdentifier("root.brand")
        }
    }

    private var demoLabel: some View {
        Text("Демоданные")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("root.demo")
    }
}

struct RootScreenTitle: View {
    @ScaledMetric(relativeTo: .title) private var fontSize = 30.0
    let tab: AppTab

    var body: some View {
        Text(title)
            .font(.system(size: fontSize, weight: .bold))
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("root.title.\(tab.rawValue)")
    }

    private var title: LocalizedStringKey {
        switch tab {
        case .products: "Мои продукты"
        case .dishes: "Что приготовим?"
        case .shopping: "Что докупить"
        case .profile: "Профиль"
        }
    }
}

extension View {
    func rootScreenHeader() -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            RootScreenHeader()
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
