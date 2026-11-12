import Foundation
import SwiftUI
import UIKit

struct DishesScreen: View {
    private enum Filter: CaseIterable {
        case all
        case ready
        case needsShopping

        var title: LocalizedStringKey {
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

    @Environment(DemoStore.self) private var store
    @ScaledMetric(relativeTo: .headline) private var sectionTitleSize = 18.0
    @State private var query = ""
    @State private var filter = Filter.all
    @FocusState private var isSearchFocused: Bool
    let onOpenProducts: () -> Void
    let tabBar: FloatingTabBar

    var body: some View {
        let availability = DishesAvailability(
            recipes: store.recipes,
            missingIngredients: store.missingIngredients(for:)
        )
        let ready = filter == .needsShopping ? [] : matchingSearch(availability.ready)
        let needsShopping = filter == .ready ? [] : matchingSearch(availability.needsShopping)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                pantryHeader(showsProductsLink: !availability.isEmpty)

                if availability.isEmpty {
                    ContentUnavailableView {
                        Label("Нет подходящих блюд", systemImage: "fork.knife")
                    } actions: {
                        Button("К продуктам", action: onOpenProducts)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        searchField
                        filters
                    }

                    if ready.isEmpty && needsShopping.isEmpty {
                        ContentUnavailableView {
                            Label("Блюда не найдены", systemImage: "magnifyingglass")
                        } actions: {
                            Button("Показать все блюда") {
                                query = ""
                                filter = .all
                            }
                        }
                    } else {
                        dishSection("Можно сейчас", entries: ready)

                        let shoppingSections = Dictionary(grouping: needsShopping) { $0.missingIngredients.count }
                        ForEach(shoppingSections.keys.sorted(), id: \.self) { count in
                            dishSection(
                                "Докупить \(productCount(count))",
                                entries: shoppingSections[count, default: []]
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .floatingTabBarInset {
            if !isSearchFocused { tabBar }
        }
        .rootScreenHeader()
        .background(Color(.demoBackground).ignoresSafeArea())
        .onDisappear { isSearchFocused = false }
    }

    private func pantryHeader(showsProductsLink: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            RootScreenTitle(tab: .dishes)

            if showsProductsLink {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        pantryCount
                        Spacer(minLength: 0)
                        productsLink
                            .padding(.trailing, 20)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        pantryCount
                        productsLink
                    }
                }
            } else {
                pantryCount
            }
        }
    }

    private var pantryCount: some View {
        Label("\(productCount(store.productIDs.count)) дома", systemImage: "refrigerator")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var productsLink: some View {
        Button(action: onOpenProducts) {
            Text("Изменить")
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("Изменить продукты дома")
    }

    private func productCount(_ count: Int) -> String {
        let unit: String
        switch (count % 100, count % 10) {
        case (11...14, _): unit = "продуктов"
        case (_, 1): unit = "продукт"
        case (_, 2...4): unit = "продукта"
        default: unit = "продуктов"
        }
        return "\(count) \(unit)"
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
        ForEach(Filter.allCases, id: \.self) { option in
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

    private func matchingSearch(_ entries: [DishesAvailability.Entry]) -> [DishesAvailability.Entry] {
        let search = query.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !search.isEmpty else { return entries }
        return entries.filter { entry in
            entry.recipe.title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                .localizedCaseInsensitiveContains(search)
        }
    }

    @ViewBuilder
    private func dishSection(_ title: LocalizedStringKey, entries: [DishesAvailability.Entry]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.system(size: sectionTitleSize, weight: .bold))
                    Spacer()
                    Text(entries.count, format: .number)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 20)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                VStack(spacing: 12) {
                    ForEach(entries) { entry in
                        NavigationLink(value: entry.recipe.id) {
                            DishCard(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("dishes.recipe.\(entry.recipe.id)")
                    }
                }
            }
        }
    }
}
