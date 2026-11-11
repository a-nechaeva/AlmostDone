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
    }

    @Environment(DemoStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var filter = Filter.all

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
                        Button("К продуктам") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    searchField
                    filters

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
                        dishSection("Докупить 1–3", entries: needsShopping)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color(.demoBackground).ignoresSafeArea())
        .navigationTitle("Блюда")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("Демоданные")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pantryHeader(showsProductsLink: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Что приготовим?")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)

            if showsProductsLink {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        pantryCount
                        Spacer()
                        productsLink
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
        Label("Продукты дома (\(store.productIDs.count))", systemImage: "refrigerator")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var productsLink: some View {
        Button {
            dismiss()
        } label: {
            Text("К продуктам")
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 44)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Найти блюдо", text: $query)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
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
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        isSelected
                            ? Color.accentColor.opacity(0.13) : Color(uiColor: .secondarySystemGroupedBackground),
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
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title)
                        .font(.headline.bold())
                    Spacer()
                    Text(entries.count, format: .number)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                ForEach(entries) { entry in
                    NavigationLink(value: Route.recipe(entry.recipe.id)) {
                        DishCard(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("dishes.recipe.\(entry.recipe.id)")
                }
            }
        }
    }
}
