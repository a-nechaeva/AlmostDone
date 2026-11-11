import SwiftUI
import UIKit

struct DishCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    let entry: DishesAvailability.Entry

    var body: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))

        layout {
            thumbnail
                .frame(width: 100, height: 100)
                .clipShape(.rect(cornerRadius: 22))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.recipe.title)
                    .font(.headline.bold())
                availabilityLabel
                    .font(.footnote)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
        .contentShape(.rect(cornerRadius: 24))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let photo {
            photo
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "fork.knife")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.accentColor.opacity(0.13))
        }
    }

    private var photo: Image? {
        switch entry.recipe.id {
        case "tomato-omelet": Image(.dishesTomatoOmelet)
        case "tomato-cheese-pasta": Image(.dishesTomatoCheesePasta)
        default: nil
        }
    }

    private var readyColor: Color {
        colorScheme == .dark ? Color(red: 0.60, green: 0.82, blue: 0.68) : Color(red: 0.20, green: 0.41, blue: 0.29)
    }

    @ViewBuilder
    private var availabilityLabel: some View {
        if entry.missingIngredients.isEmpty {
            Text("Все продукты есть")
                .foregroundStyle(readyColor)
        } else {
            let names = entry.missingIngredients.map(\.name).joined(separator: ", ")
            Text(names)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Докупить \(names)")
        }
    }
}
