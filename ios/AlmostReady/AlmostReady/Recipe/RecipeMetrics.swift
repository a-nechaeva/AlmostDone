import SwiftUI

struct RecipeMetrics: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let presentation: RecipePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if presentation.minutes != nil || presentation.nutrition?.kilocalories != nil
                || presentation.servings != nil
            {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    if let minutes = presentation.minutes {
                        metric("\(minutes) мин", caption: "всего")
                    }
                    if let kilocalories = presentation.nutrition?.kilocalories {
                        metric("\(kilocalories) ккал", caption: "на порцию")
                    }
                    if let servings = presentation.servings {
                        metric("\(servings.count)", caption: servings.unit)
                    }
                }
            }

            if let macros = presentation.nutrition?.macros {
                Text("На порцию: \(macros)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !presentation.allergens.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Аллергены")
                        .font(.subheadline.bold())
                        .accessibilityAddTraits(.isHeader)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            allergenChips
                        }
                        .fixedSize(horizontal: true, vertical: false)

                        VStack(alignment: .leading, spacing: 8) {
                            allergenChips
                        }
                    }
                }
            }
        }
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 12, alignment: .topLeading),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 3
        )
    }

    private func metric(_ value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.headline.bold())
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
        .padding(12)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 18))
    }

    private var allergenChips: some View {
        ForEach(presentation.allergens, id: \.self) { allergen in
            Text(allergen)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: .capsule)
        }
    }
}
