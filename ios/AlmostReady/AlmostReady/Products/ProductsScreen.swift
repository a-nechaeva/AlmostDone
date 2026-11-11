import SwiftUI

struct ProductsScreen: View {
    @Environment(DemoStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        List {
            Section("Продукты дома") {
                ForEach(store.products) { ingredient in
                    Label(ingredient.name, systemImage: "basket")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.demoBackground))
        .safeAreaInset(edge: .bottom) {
            NavigationLink(value: Route.dishes) {
                Text("Подобрать блюда")
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(Color(.demoBackground))
        }
        .navigationTitle("Мои продукты")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("Демоданные")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
