import Foundation
import SwiftUI
import UIKit

struct DishesScreen: View {
    @Environment(DemoStore.self) private var store
    @Environment(\.floatingTabBarHeight) private var tabBarHeight
    @ScaledMetric(relativeTo: .headline) private var sectionTitleSize = 18.0
    @State private var query = ""
    @State private var filter = DishesFilter.all
    @FocusState.Binding var isSearchFocused: Bool
    let onOpenProducts: () -> Void

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
                    DishesControls(query: $query, filter: $filter, isSearchFocused: $isSearchFocused)

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
                                "Докупить \(dishesProductCount(count))",
                                entries: shoppingSections[count, default: []]
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .safeAreaPadding(.bottom, tabBarHeight)
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
        Label("\(dishesProductCount(store.productIDs.count)) дома", systemImage: "refrigerator")
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
                        NavigationLink(
                            value: RecipeRequest(id: entry.recipe.id, servings: nil, excludedAllergenIDs: [])
                        ) {
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
