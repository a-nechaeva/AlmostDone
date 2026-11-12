import Foundation

struct RecommendationGraphContent {
    struct Dish: Identifiable {
        let id: String
        let card: RecommendationCard
        let request: RecipeRequest
    }

    struct Extension: Identifiable {
        let id: String
        let from: String
        let items: [ShoppingPackage]
        let cost: ShoppingMoney?
    }

    struct PurchaseSet: Identifiable {
        let id: String
        let title: String
        let items: [ShoppingPackage]
        let cost: ShoppingMoney?
        let extensions: [Extension]
        let dishes: [Dish]
    }

    let homeTitle: String
    let homeDishes: [Dish]
    let purchaseSets: [PurchaseSet]
    let hasUnrepresentedDishes: Bool
    let revision: AccountRevision

    var isEmpty: Bool { homeDishes.isEmpty && purchaseSets.isEmpty }

    init(response: APIResponse<RecommendationGraph>) throws {
        let value = response.value
        let graph = value.graph
        let invalid = APIClientError.invalidResponse(response.metadata)
        revision = try AccountRevision(etag: response.metadata.etag, stateVersion: value.stateVersion)

        var nodes: [String: RecommendationGraph.Node] = [:]
        var home: RecommendationGraph.Node?
        var dishes: [String: Dish] = [:]
        var recipeIDs = Set(graph.unrepresentedRecipeIDs)
        for node in graph.nodes {
            guard !node.id.isEmpty, nodes.updateValue(node, forKey: node.id) == nil else { throw invalid }
            switch node.kind {
            case .home:
                guard home == nil, node.level == 0 else { throw invalid }
                home = node
            case .purchase(let purchase):
                guard (1...3).contains(node.level), purchase.items.count == node.level else { throw invalid }
            case .recipe(let recipe):
                let card = recipe.card
                guard recipe.id == card.id, card.servings == value.servings,
                    (0...3).contains(node.level), card.availability.missingCount == node.level,
                    recipeIDs.insert(recipe.id).inserted
                else { throw invalid }
                dishes[node.id] = Dish(
                    id: node.id, card: card,
                    request: RecipeRequest(
                        id: recipe.id, servings: value.servings,
                        excludedAllergenIDs: value.filters.excludedAllergenIDs
                    )
                )
            }
        }
        guard let home else { throw invalid }

        var linkedDishes: [String: [Dish]] = [:]
        var extensions: [String: [Extension]] = [:]
        var linkedRecipeNodes = Set<String>()
        for edge in graph.edges {
            guard let source = nodes[edge.source], let target = nodes[edge.target] else { throw invalid }
            switch edge.kind {
            case .unlocks:
                guard let dish = dishes[edge.target], dishes[edge.source] == nil, source.level == target.level,
                    linkedRecipeNodes.insert(edge.target).inserted
                else { throw invalid }
                linkedDishes[edge.source, default: []].append(dish)
            case .extends(let items, let cost):
                guard case .purchase = target.kind, dishes[edge.source] == nil,
                    source.level < target.level, !items.isEmpty
                else { throw invalid }
                extensions[edge.target, default: []].append(
                    Extension(id: source.id, from: source.label, items: items, cost: cost))
            }
        }
        guard linkedRecipeNodes.count == dishes.count else { throw invalid }

        homeTitle = home.label
        homeDishes = linkedDishes[home.id, default: []]
        purchaseSets = try graph.nodes.compactMap { node in
            guard case .purchase(let purchase) = node.kind else { return nil }
            let alternatives = linkedDishes[node.id, default: []]
            let paths = extensions[node.id, default: []]
            guard !alternatives.isEmpty, alternatives.count == purchase.dishCount,
                !paths.isEmpty, Set(paths.map(\.id)).count == paths.count
            else { throw invalid }
            return PurchaseSet(
                id: node.id, title: node.label, items: purchase.items, cost: purchase.cost,
                extensions: paths, dishes: alternatives
            )
        }
        hasUnrepresentedDishes = !graph.unrepresentedRecipeIDs.isEmpty
    }
}
