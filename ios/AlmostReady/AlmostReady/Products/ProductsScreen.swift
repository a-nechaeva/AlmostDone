import SwiftUI

struct ProductsScreen: View {
    @Environment(DemoStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.floatingTabBarHeight) private var tabBarHeight
    @ScaledMetric(relativeTo: .subheadline) private var labelSize = 14.0
    @Binding var isSearchPresented: Bool
    let onOpenDishes: () -> Void

    private var palette: ProductsPalette { ProductsPalette(colorScheme: colorScheme) }

    var body: some View {
        let products = store.products

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RootScreenTitle(tab: .products)

                Text(summary(for: products.count))
                    .font(.system(size: labelSize))
                    .foregroundStyle(palette.secondaryText)
                    .accessibilityIdentifier("products.summary")
                    .padding(.top, 8)

                searchLink
                    .padding(.top, 24)

                LazyVStack(alignment: .leading, spacing: 8) {
                    if products.isEmpty {
                        Text("Список пуст. Найдите продукт, чтобы добавить его")
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryText)
                            .accessibilityIdentifier("products.home.empty")
                    } else {
                        ForEach(products) { ingredient in
                            productRow(ingredient)
                        }
                    }
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            dishesLink
                .padding(.bottom, tabBarHeight)
        }
        .rootScreenHeader()
        .background(Color(.demoBackground).ignoresSafeArea())
        .navigationDestination(isPresented: $isSearchPresented) {
            ProductsSearchScreen()
        }
    }

    private var searchLink: some View {
        Button {
            isSearchPresented = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text("Добавить продукт")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: labelSize))
            .foregroundStyle(palette.secondaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 48)
            .background(palette.card, in: .rect(cornerRadius: 18))
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("products.search.open")
    }

    private func productRow(_ ingredient: Ingredient) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bag")
                .foregroundStyle(palette.secondaryText)
                .frame(width: 36, height: 36)
                .background(palette.tile, in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)

            Text(ingredient.name)
                .font(.system(size: labelSize, weight: .medium))
                .foregroundStyle(palette.titleText)
                .accessibilityIdentifier("products.home.\(ingredient.id)")

            Spacer(minLength: 0)

            Button(role: .destructive) {
                store.productIDs.remove(ingredient.id)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Удалить продукт «\(ingredient.name)»")
            .accessibilityIdentifier("products.remove.\(ingredient.id)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .frame(minHeight: 56)
        .background(palette.card, in: .rect(cornerRadius: 18))
    }

    private var dishesLink: some View {
        Button(action: onOpenDishes) {
            Text("Подобрать блюда")
                .font(.system(size: labelSize, weight: .bold))
                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(palette.action, in: .rect(cornerRadius: 16))
                .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("products.dishes")
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(Color(.demoBackground), ignoresSafeAreaEdges: [])
    }

    private func summary(for count: Int) -> String {
        let noun: String
        switch (count % 10, count % 100) {
        case (_, 11...14): noun = "продуктов"
        case (1, _): noun = "продукт"
        case (2...4, _): noun = "продукта"
        default: noun = "продуктов"
        }
        let total = "\(count) \(noun)"
        return count == 0 ? total : "\(total) · всё под рукой"
    }
}

struct ProductsPalette {
    let colorScheme: ColorScheme

    var card: Color {
        colorScheme == .dark ? Color(.secondarySystemGroupedBackground) : .white
    }

    var tile: Color {
        colorScheme == .dark
            ? Color(.tertiarySystemFill)
            : Color(red: 238.0 / 255, green: 236.0 / 255, blue: 231.0 / 255)
    }

    var titleText: Color {
        colorScheme == .dark ? .primary : Color(red: 32.0 / 255, green: 32.0 / 255, blue: 30.0 / 255)
    }

    var secondaryText: Color {
        colorScheme == .dark ? .secondary : Color(red: 108.0 / 255, green: 107.0 / 255, blue: 102.0 / 255)
    }

    var action: Color {
        colorScheme == .dark ? .accentColor : Color(red: 182.0 / 255, green: 76.0 / 255, blue: 53.0 / 255)
    }
}
