import Foundation

nonisolated struct DishesAdvancedFilters: Hashable, Sendable {
    enum Equipment: String, CaseIterable, Identifiable, Sendable {
        case stove, oven, microwave

        var id: Self { self }

        var title: String {
            switch self {
            case .stove: "Плита"
            case .oven: "Духовка"
            case .microwave: "Микроволновка"
            }
        }
    }

    var maxMinutes: Int?
    var maxKcalPerServing: Decimal?
    var equipment = Set(Equipment.allCases)
    var excludedAllergenIDs: Set<String> = []

    var equipmentIDs: [String] {
        Equipment.allCases.filter { equipment.contains($0) }.map(\.rawValue) + ["no_cook"]
    }
}

nonisolated struct DishesFilterNumbers {
    let locale: Locale

    func kcalText(_ amount: Decimal?) -> String {
        amount?.description.replacingOccurrences(of: ".", with: locale.decimalSeparator ?? ".") ?? ""
    }

    func applying(minutes: String, kcal: String, to draft: DishesAdvancedFilters) -> DishesAdvancedFilters? {
        let minutes = minutes.trimmingCharacters(in: .whitespacesAndNewlines)
        let kcal = kcal.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMinutes = asciiDigits(in: minutes)
        let normalizedKcal = asciiDigits(in: kcal)
            .replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")
            .replacingOccurrences(of: ",", with: ".")

        var filters = draft
        filters.maxMinutes = Int(normalizedMinutes)
        guard minutes.isEmpty || filters.maxMinutes.map({ $0 >= 1 }) == true else { return nil }
        filters.maxKcalPerServing = nil
        if !kcal.isEmpty {
            guard normalizedKcal.wholeMatch(of: #/(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)/#) != nil,
                let amount = Decimal(string: normalizedKcal, locale: Locale(identifier: "en_US_POSIX"))
            else { return nil }
            filters.maxKcalPerServing = amount
        }
        return filters
    }

    private func asciiDigits(in text: String) -> String {
        text.map { character in
            guard let digit = character.wholeNumberValue, digit < 10,
                character.unicodeScalars.count == 1, character.unicodeScalars.first?.properties.numericType == .decimal
            else {
                return String(character)
            }
            return String(digit)
        }.joined()
    }
}
