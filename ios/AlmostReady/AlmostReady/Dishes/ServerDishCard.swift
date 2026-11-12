import Foundation
import SwiftUI
import UIKit

struct ServerDishCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var titleSize = 18.0
    @State private var photo = RecipePhoto.unavailable

    let card: RecommendationCard
    let repository: RecommendationsRepository

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
                Text(card.title)
                    .font(.system(size: titleSize, weight: .bold))
                Text(time)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(nutrition)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(availability)
                    .font(.caption)
                if card.availability.status != .ready {
                    Text(price)
                        .font(.caption)
                }
                if !card.availability.unknownQuantityIDs.isEmpty {
                    Text("У некоторых продуктов дома не указано количество")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if card.suitability.status == .unknown {
                    Label("Пригодность неизвестна", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                }
                ForEach(card.suitability.reasons.indices, id: \.self) { index in
                    Text(card.suitability.reasons[index].message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
        .contentShape(.rect(cornerRadius: 24))
        .task(id: card.photoURL) {
            guard card.photoURL != nil, case .unavailable = photo else { return }
            let session = repository.session
            guard session.isCurrent(repository.account),
                let response = try? await session.publicData(path: ["recipes", card.id, "photo"]),
                !Task.isCancelled, session.isCurrent(repository.account)
            else { return }
            photo = RecipePhoto(response: response)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if case .image(let image) = photo {
            Image(uiImage: image)
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

    private var time: String {
        card.minutes.map { "\($0.formatted()) мин" } ?? "Время неизвестно"
    }

    private var nutrition: String {
        guard let nutrition = card.nutrition else { return "КБЖУ на порцию неизвестны" }
        let format = Decimal.FormatStyle.number.precision(.fractionLength(0...1))
        let energy = nutrition.kcal.formatted(format)
        let protein = nutrition.protein.formatted(format)
        let fat = nutrition.fat.formatted(format)
        let carbs = nutrition.carbs.formatted(format)
        return "\(energy) ккал на порцию · Б \(protein) · Ж \(fat) · У \(carbs) г"
    }

    private var availability: String {
        let count = card.availability.missingCount
        let availability: RecipePresentation.Availability =
            switch card.availability.status {
            case .ready: .ready
            case .missing: .missing(count)
            case .unknown: .unknown(missingCount: count)
            }
        return availability.label
    }

    private var price: String {
        guard let buyCost = card.buyCost else { return "Стоимость докупки неизвестна" }
        let rubles = Decimal(buyCost.minorUnits) / 100
        let amount = rubles.formatted(.currency(code: "RUB"))
        return "Докупка за \(amount)"
    }
}
