import Foundation
import XCTest

@testable import AlmostReady

enum RecommendationGraphFixture {
    static let requestID = UUID(uuid: (0, 0, 0, 0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0, 0, 1))
    static let snapshotID = "opaque/snapshot"
    static let servings = 4

    @MainActor
    static func snapshot(id: String = snapshotID) throws -> RecommendationGraphSnapshot {
        let data = try JSONSerialization.data(withJSONObject: [
            "request_id": requestID.uuidString, "snapshot_id": id, "state_version": 7,
            "catalog_version": "catalog-1", "servings": servings, "visibility": "visible",
            "visible_total": 5, "hidden_total": 0, "unknown_total": 1, "items": [],
            "page": ["next_cursor": "next", "has_more": true]
        ])
        let page = try JSONDecoder().decode(RecommendationPage.self, from: data)
        return RecommendationGraphSnapshot(DishesSnapshot(page: page, context: context))
    }

    nonisolated static var context: ServerDishesModel.Context {
        .init(
            query: "обед",
            advancedFilters: .init(
                maxMinutes: 30, maxKcalPerServing: 400.5, equipment: [.stove],
                excludedAllergenIDs: ["eggs", "nuts"]
            ),
            servings: servings, stateVersion: 7
        )
    }

    static func response(
        _ request: URLRequest, id: String = snapshotID, version: Int = 7, readyOnly: Bool = false, empty: Bool = false,
        unrepresented: Bool = true, requestID: UUID = requestID, etag: String? = nil,
        filters: [String: Any]? = nil, expiresAt: Date = .now.addingTimeInterval(600)
    ) throws -> (Data, URLResponse) {
        let rice = item("rice", name: "Рис", count: 1, price: 12_050)
        let extraRice = item("rice", name: "Рис", count: 2, price: 24_100)
        let allRice = item("rice", name: "Рис", count: 3, price: 36_150)
        let milk = item("milk", name: "Молоко", count: 1, price: nil)
        let home: [String: Any] = ["id": "home-node", "kind": "home", "label": "Дома", "level": 0]
        let nodes: [[String: Any]] =
            empty
            ? [home]
            : readyOnly
                ? [home, recipe("ready-node", id: "ready", level: 0)]
                : [
                    home,
                    purchase("rice-set", label: "Рис", items: [rice], cost: 12_050, dishCount: 2),
                    purchase("milk-set", label: "Молоко", items: [milk], cost: nil, dishCount: 1),
                    purchase("both-set", label: "Рис и молоко", items: [allRice, milk], cost: nil, dishCount: 1),
                    recipe("ready-node", id: "ready", level: 0),
                    recipe("rice-node", id: "rice", level: 1, suitabilityUnknown: true),
                    recipe("rice-alt-node", id: "rice-alternative", level: 1),
                    recipe("milk-node", id: "milk", level: 1),
                    recipe("both-node", id: "both", level: 2)
                ]
        let edges: [[String: Any]] =
            empty
            ? []
            : readyOnly
                ? [unlocks("home-node", "ready-node")]
                : [
                    extends("home-node", "rice-set", add: [rice], price: 12_050),
                    extends("home-node", "milk-set", add: [milk], price: nil),
                    extends("rice-set", "both-set", add: [extraRice, milk], price: nil),
                    extends("milk-set", "both-set", add: [allRice], price: 36_150),
                    unlocks("home-node", "ready-node"),
                    unlocks("rice-set", "rice-node"),
                    unlocks("rice-set", "rice-alt-node"),
                    unlocks("milk-set", "milk-node"),
                    unlocks("both-set", "both-node")
                ]
        return try SessionFixture.response(
            request,
            body: [
                "request_id": requestID.uuidString, "snapshot_id": id, "state_version": version,
                "expires_at": expiresAt.ISO8601Format(Date.ISO8601FormatStyle(includingFractionalSeconds: true)),
                "catalog_version": "catalog-1", "servings": servings,
                "visibility": "visible",
                "filters": filters ?? [
                    "q": "обед", "mode": "all", "max_minutes": 30, "max_kcal_per_serving": 400.5,
                    "equipment": ["stove", "no_cook"], "exclude_allergens": ["eggs", "nuts"]
                ],
                "graph": [
                    "scope": "snapshot", "nodes": nodes, "edges": edges,
                    "unrepresented_recipe_ids": unrepresented ? ["many-products"] : []
                ]
            ],
            etag: etag ?? #""state-\#(version)""#
        )
    }

    private static func item(_ id: String, name: String, count: Int, price: Int?) -> [String: Any] {
        [
            "key": "\(id):standard", "ingredient_id": id, "package_id": "standard", "name": name,
            "package_quantity": ["value": id == "milk" ? 500 : 250, "unit": id == "milk" ? "ml" : "g"],
            "package_count": count, "total_price": money(price)
        ]
    }

    private static func purchase(
        _ id: String, label: String, items: [[String: Any]], cost: Int?, dishCount: Int
    ) -> [String: Any] {
        [
            "id": id, "kind": "purchase", "label": label, "level": items.count, "shopping_items": items,
            "cost": money(cost), "dish_count": dishCount
        ]
    }

    private static func recipe(_ node: String, id: String, level: Int, suitabilityUnknown: Bool = false) -> [String:
        Any]
    {
        [
            "id": node, "kind": "recipe", "label": id, "level": level, "recipe_id": id,
            "recipe": DishesFixture.card(
                id, missing: level, servings: servings, suitabilityUnknown: suitabilityUnknown)
        ]
    }

    private static func extends(_ source: String, _ target: String, add: [[String: Any]], price: Int?) -> [String: Any]
    {
        ["source": source, "target": target, "kind": "extends", "add": add, "add_cost": money(price)]
    }

    private static func unlocks(_ source: String, _ target: String) -> [String: Any] {
        ["source": source, "target": target, "kind": "unlocks"]
    }

    private static func money(_ price: Int?) -> Any {
        if let price { return ["minor_units": price, "currency": "RUB"] as [String: Any] }
        return NSNull()
    }
}
