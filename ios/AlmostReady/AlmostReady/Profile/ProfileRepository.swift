import Foundation

nonisolated struct ServerProfile: Decodable, Sendable {
    let userID: String
    let displayName: String?
    let preferences: ProfilePreferences
    let unsupportedRestrictions: [String]
    let stateVersion: Int

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case preferences
        case unsupportedRestrictions = "unsupported_restrictions"
        case stateVersion = "state_version"
    }
}

nonisolated struct ProfilePreferences: Codable, Sendable, Equatable {
    var foodType: String
    var excludedAllergens: Set<String>
    var glutenFree: Bool
    var lactoseFree: Bool
    var diabetes: Bool
    var dietTableID: String?

    private enum CodingKeys: String, CodingKey {
        case foodType = "food_type"
        case excludedAllergens = "excluded_allergens"
        case glutenFree = "gluten_free"
        case lactoseFree = "lactose_free"
        case diabetes
        case dietTableID = "diet_table_id"
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(foodType, forKey: .foodType)
        try values.encode(excludedAllergens.sorted(), forKey: .excludedAllergens)
        try values.encode(glutenFree, forKey: .glutenFree)
        try values.encode(lactoseFree, forKey: .lactoseFree)
        try values.encode(diabetes, forKey: .diabetes)
        try values.encode(dietTableID, forKey: .dietTableID)
    }

    func applyingChanges(from base: Self, to latest: Self) -> Self {
        var merged = latest
        if foodType != base.foodType { merged.foodType = foodType }
        if glutenFree != base.glutenFree { merged.glutenFree = glutenFree }
        if lactoseFree != base.lactoseFree { merged.lactoseFree = lactoseFree }
        if diabetes != base.diabetes { merged.diabetes = diabetes }
        if dietTableID != base.dietTableID { merged.dietTableID = dietTableID }
        merged.excludedAllergens.formUnion(excludedAllergens.subtracting(base.excludedAllergens))
        merged.excludedAllergens.subtract(base.excludedAllergens.subtracting(excludedAllergens))
        return merged
    }
}

nonisolated enum ProfileOptionSupport: String, Decodable, Sendable {
    case supported, unsupported, informational
}

nonisolated struct ProfileAllergenOption: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let support: ProfileOptionSupport
}

nonisolated struct ProfileDietaryOption: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let support: ProfileOptionSupport
    let binding: ProfileDietaryBinding?

    private enum CodingKeys: String, CodingKey {
        case id, name, support
        case binding = "profile_binding"
    }
}

nonisolated enum ProfileDietaryBinding: Decodable, Sendable {
    enum Field: String, Decodable, Sendable {
        case foodType = "food_type"
        case glutenFree = "gluten_free"
        case lactoseFree = "lactose_free"
        case diabetes
        case dietTable = "diet_table_id"
    }

    case foodType(String)
    case restriction(WritableKeyPath<ProfilePreferences, Bool> & Sendable)
    case dietTable(String)

    private enum CodingKeys: String, CodingKey {
        case field, value
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let field = try values.decode(Field.self, forKey: .field)
        switch field {
        case .foodType:
            self = .foodType(try values.decode(String.self, forKey: .value))
        case .dietTable:
            self = .dietTable(try values.decode(String.self, forKey: .value))
        case .glutenFree, .lactoseFree, .diabetes:
            guard try values.decode(Bool.self, forKey: .value) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value, in: values, debugDescription: "Dietary restrictions must bind to true"
                )
            }
            switch field {
            case .glutenFree: self = .restriction(\.glutenFree)
            case .lactoseFree: self = .restriction(\.lactoseFree)
            default: self = .restriction(\.diabetes)
            }
        }
    }

    var isSingleChoice: Bool {
        if case .restriction = self { return false }
        return true
    }

    func isSelected(in preferences: ProfilePreferences) -> Bool {
        switch self {
        case .foodType(let value): preferences.foodType == value
        case .restriction(let keyPath): preferences[keyPath: keyPath]
        case .dietTable(let value): preferences.dietTableID == value
        }
    }

    func select(in preferences: inout ProfilePreferences) {
        switch self {
        case .foodType(let value): preferences.foodType = value
        case .restriction(let keyPath): preferences[keyPath: keyPath].toggle()
        case .dietTable(let value): preferences.dietTableID = value
        }
    }
}

nonisolated struct ProfileDictionary<Item: Decodable & Sendable>: Decodable, Sendable {
    let items: [Item]
}

nonisolated struct ProfileCatalogs: Sendable {
    let allergens: [ProfileAllergenOption]
    let dietary: [ProfileDietaryOption]
}

nonisolated struct ProfileSnapshot: Sendable {
    let value: ServerProfile
    let revision: AccountRevision

    init(_ response: APIResponse<ServerProfile>) throws {
        value = response.value
        revision = try AccountRevision(etag: response.metadata.etag, stateVersion: value.stateVersion)
    }
}

struct ProfileSaveOperation {
    let etag: String
    let preferences: ProfilePreferences
    let key = UUID().uuidString
}

@MainActor
struct ProfileRepository {
    let session: SessionStore
    let account: AccountSession

    func profile() async throws -> ProfileSnapshot {
        let response = try await session.json(ServerProfile.self, for: APIRequest(path: ["me"]), account: account)
        return try ProfileSnapshot(response)
    }

    func catalogs() async throws -> ProfileCatalogs {
        async let allergens = session.json(
            ProfileDictionary<ProfileAllergenOption>.self, for: APIRequest(path: ["allergens"]), account: account
        )
        async let dietary = session.json(
            ProfileDictionary<ProfileDietaryOption>.self, for: APIRequest(path: ["dietary-options"]), account: account
        )
        return try await ProfileCatalogs(allergens: allergens.value.items, dietary: dietary.value.items)
    }

    func save(_ operation: ProfileSaveOperation) async throws -> APIResponse<ServerProfile> {
        let request = APIRequest(
            path: ["me"], method: .patch,
            headers: .init(ifMatch: operation.etag, idempotencyKey: operation.key),
            jsonBody: ProfileUpdate(preferences: operation.preferences)
        )
        return try await session.json(ServerProfile.self, for: request, account: account)
    }

    private nonisolated struct ProfileUpdate: Encodable, Sendable {
        let preferences: ProfilePreferences
    }
}
