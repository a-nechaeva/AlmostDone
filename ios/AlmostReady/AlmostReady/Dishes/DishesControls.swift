import SwiftUI
import UIKit

nonisolated enum DishesFilter: String, CaseIterable, Codable, Sendable {
    case all
    case ready = "now"
    case needsShopping = "buy_1_3"

    @MainActor var title: LocalizedStringKey {
        switch self {
        case .all: "Все"
        case .ready: "Сейчас"
        case .needsShopping: "Докупить 1–3"
        }
    }

    var minimumWidth: CGFloat {
        switch self {
        case .all: 66
        case .ready: 94
        case .needsShopping: 156
        }
    }
}

struct DishesControls: View {
    @Binding var query: String
    @Binding var filter: DishesFilter
    @FocusState.Binding var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField
            filters
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(
                "Найти блюдо",
                text: $query,
                prompt: Text("Найти блюдо").foregroundColor(Color(uiColor: .label).opacity(0.6))
            )
            .focused($isSearchFocused)
            .submitLabel(.done)
            .onSubmit { isSearchFocused = false }
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { filterButtons }
            VStack(alignment: .leading, spacing: 0) { filterButtons }
        }
    }

    private var filterButtons: some View {
        ForEach(DishesFilter.allCases, id: \.self) { option in
            let isSelected = option == filter
            Button {
                filter = option
            } label: {
                Text(option.title)
                    .font(.footnote.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(minWidth: option.minimumWidth, minHeight: 36)
                    .background(
                        isSelected
                            ? Color.accentColor.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground),
                        in: .capsule
                    )
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

func dishesProductCount(_ count: Int) -> String {
    let unit: String
    switch (count % 100, count % 10) {
    case (11...14, _): unit = "продуктов"
    case (_, 1): unit = "продукт"
    case (_, 2...4): unit = "продукта"
    default: unit = "продуктов"
    }
    return "\(count) \(unit)"
}
