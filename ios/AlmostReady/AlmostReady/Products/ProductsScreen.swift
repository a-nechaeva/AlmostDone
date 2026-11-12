import SwiftUI

struct ProductsScreen: View {
    @Environment(DemoStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool
    let onOpenDishes: () -> Void
    let tabBar: FloatingTabBar

    private var isSearching: Bool {
        isSearchFocused || !query.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            RootScreenTitle(tab: .products)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 12)

            searchBar
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if isSearching {
                        searchResults
                    } else {
                        productsAtHome
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.never)
            // Search results and pantry rows share IDs but have different actions.
            .id(isSearching)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                dishesLink
            }
            .floatingTabBarInset {
                if !isSearchFocused { tabBar }
            }
        }
        .rootScreenHeader()
        .background(Color(.demoBackground).ignoresSafeArea())
        .onDisappear(perform: dismissKeyboard)
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Добавить продукт", text: $query)
                    .focused($isSearchFocused)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(dismissKeyboard)
                    .accessibilityIdentifier("products.search")
                    .frame(minHeight: 48)
            }
            .padding(.horizontal, 16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))

            if isSearching {
                Button(action: closeSearch) {
                    Text("Отмена")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("products.search.cancel")
            }
        }
    }

    @ViewBuilder
    private var productsAtHome: some View {
        let products = store.products
        Text("Продукты дома")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)

        if products.isEmpty {
            Text("Список пуст. Найдите продукт, чтобы добавить его")
                .foregroundStyle(.secondary)
        } else {
            ForEach(products) { ingredient in
                productRow(ingredient)
            }
        }
    }

    private func productRow(_ ingredient: Ingredient) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bag")
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)

            Text(ingredient.name)
                .accessibilityIdentifier("products.home.\(ingredient.id)")
            Spacer(minLength: 0)
            Button(role: .destructive) {
                store.productIDs.remove(ingredient.id)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Удалить продукт «\(ingredient.name)»")
            .accessibilityIdentifier("products.remove.\(ingredient.id)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(minHeight: 56)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }

    @ViewBuilder
    private var searchResults: some View {
        let results = ProductsSearch.matches(query, excluding: store.productIDs)
        Text("Из каталога ингредиентов")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)

        if results.isEmpty {
            Text("Нет продуктов для добавления по этому запросу")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("products.search.empty")
        } else {
            ForEach(results) { ingredient in
                Button {
                    store.productIDs.insert(ingredient.id)
                    closeSearch()
                } label: {
                    HStack {
                        Text(ingredient.name)
                        Spacer(minLength: 12)
                        Image(systemName: "plus")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
                    .contentShape(.rect(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Добавить продукт «\(ingredient.name)»")
                .accessibilityIdentifier("products.add.\(ingredient.id)")
            }
        }
    }

    private var dishesLink: some View {
        Button(action: onOpenDishes) {
            Text("Подобрать блюда")
                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("products.dishes")
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func closeSearch() {
        dismissKeyboard()
        query = ""
    }

    private func dismissKeyboard() {
        isSearchFocused = false
    }
}
