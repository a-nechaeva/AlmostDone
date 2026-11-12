import SwiftUI

struct ProductsSearchScreen: View {
    @Environment(DemoStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFocused: Bool
    @State private var query = ""

    private var palette: ProductsPalette { ProductsPalette(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
                .padding(.horizontal, 20)
                .padding(.top, 20)

            ScrollView {
                results
                    .padding(.horizontal, 20)
                    .padding(.top, 32)
                    .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.never)
        }
        .defaultFocus($isSearchFocused, true)
        .toolbar(.hidden, for: .navigationBar)
        .background(Color(.demoBackground).ignoresSafeArea())
        .accessibilityAction(.escape, closeSearch)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: closeSearch) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18))
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Назад")
            .accessibilityIdentifier("products.search.back")

            Text("Добавить продукт")
                .font(.headline.weight(.medium))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("products.search.title")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(palette.titleText)
        .padding(.leading, 8)
        .padding(.trailing, 20)
    }

    private var searchField: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .frame(width: 24)
                .foregroundStyle(palette.secondaryText)
                .accessibilityHidden(true)

            TextField("Добавить продукт", text: $query)
                .foregroundStyle(palette.titleText)
                .focused($isSearchFocused)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { isSearchFocused = false }
                .accessibilityIdentifier("products.search")

            if !query.isEmpty {
                Button {
                    query = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(palette.secondaryText)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить поиск")
                .accessibilityIdentifier("products.search.clear")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .frame(minHeight: 56)
        .background(palette.card, in: .rect(cornerRadius: 18))
    }

    private var results: some View {
        let matches = ProductsSearch.matches(query, excluding: store.productIDs)

        return VStack(alignment: .leading, spacing: 18) {
            Text("Из каталога ингредиентов")
                .font(.footnote.weight(.medium))
                .foregroundStyle(palette.secondaryText)
                .accessibilityAddTraits(.isHeader)

            if matches.isEmpty {
                Text("Нет продуктов для добавления по этому запросу")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .accessibilityIdentifier("products.search.empty")
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(matches) { ingredient in
                        resultCard(ingredient)
                    }
                }

                Text("Выбирайте продукт из подсказок, чтобы в списке не было дублей")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resultCard(_ ingredient: Ingredient) -> some View {
        Button {
            store.productIDs.insert(ingredient.id)
            closeSearch()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ingredient.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.titleText)
                    Text("Выбрать продукт")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "plus")
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 16)
            .padding(.trailing, 20)
            .padding(.vertical, 12)
            .frame(minHeight: 72)
            .background(palette.card, in: .rect(cornerRadius: 18))
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Добавить продукт «\(ingredient.name)»")
        .accessibilityIdentifier("products.add.\(ingredient.id)")
    }

    private func closeSearch() {
        isSearchFocused = false
        dismiss()
    }
}
