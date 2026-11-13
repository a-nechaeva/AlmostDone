import Foundation

nonisolated struct RecommendationGraph: Decodable, Sendable {
    struct Graph: Decodable, Sendable {
        enum Scope: String, Decodable, Sendable {
            case snapshot
        }

        let scope: Scope
        let nodes: [Node]
        let edges: [Edge]
        let unrepresentedRecipeIDs: [String]

        private enum CodingKeys: String, CodingKey {
            case scope, nodes, edges
            case unrepresentedRecipeIDs = "unrepresented_recipe_ids"
        }
    }

    struct Node: Decodable, Identifiable, Sendable {
        struct Purchase: Sendable {
            let items: [ShoppingPackage]
            let cost: ShoppingMoney?
            let dishCount: Int
        }

        struct Recipe: Sendable {
            let id: String
            let card: RecommendationCard
        }

        enum Kind: Sendable {
            case home
            case purchase(Purchase)
            case recipe(Recipe)
        }

        let id: String
        let label: String
        let level: Int
        let kind: Kind

        private enum Discriminator: String, Decodable {
            case home, purchase, recipe
        }

        private enum CodingKeys: String, CodingKey {
            case id, label, level, kind, cost, recipe
            case shoppingItems = "shopping_items"
            case dishCount = "dish_count"
            case recipeID = "recipe_id"
        }

        init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            id = try fields.decode(String.self, forKey: .id)
            label = try fields.decode(String.self, forKey: .label)
            level = try fields.decode(Int.self, forKey: .level)
            switch try fields.decode(Discriminator.self, forKey: .kind) {
            case .home:
                kind = .home
            case .purchase:
                kind = .purchase(
                    Purchase(
                        items: try fields.decode([ShoppingPackage].self, forKey: .shoppingItems),
                        cost: try fields.decode(ShoppingMoney?.self, forKey: .cost),
                        dishCount: try fields.decode(Int.self, forKey: .dishCount)
                    ))
            case .recipe:
                kind = .recipe(
                    Recipe(
                        id: try fields.decode(String.self, forKey: .recipeID),
                        card: try fields.decode(RecommendationCard.self, forKey: .recipe)
                    ))
            }
        }
    }

    struct Edge: Decodable, Sendable {
        enum Kind: Sendable {
            case extends(add: [ShoppingPackage], cost: ShoppingMoney?)
            case unlocks
        }

        let source: String
        let target: String
        let kind: Kind

        private enum Discriminator: String, Decodable {
            case extends, unlocks
        }

        private enum CodingKeys: String, CodingKey {
            case source, target, kind, add
            case addCost = "add_cost"
        }

        init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            source = try fields.decode(String.self, forKey: .source)
            target = try fields.decode(String.self, forKey: .target)
            switch try fields.decode(Discriminator.self, forKey: .kind) {
            case .extends:
                kind = .extends(
                    add: try fields.decode([ShoppingPackage].self, forKey: .add),
                    cost: try fields.decode(ShoppingMoney?.self, forKey: .addCost)
                )
            case .unlocks:
                kind = .unlocks
            }
        }
    }

    let requestID: UUID
    let snapshotID: String
    let expiresAt: String
    let stateVersion: Int
    let catalogVersion: String
    let servings: Int
    let filters: RecommendationRequest.Filters
    let visibility: RecommendationRequest.Visibility
    let graph: Graph

    private enum CodingKeys: String, CodingKey {
        case servings, filters, visibility, graph
        case requestID = "request_id"
        case snapshotID = "snapshot_id"
        case expiresAt = "expires_at"
        case stateVersion = "state_version"
        case catalogVersion = "catalog_version"
    }
}
