import Foundation
import XCTest

@testable import AlmostReady

actor DishesRequestLog {
    private(set) var requests: [URLRequest] = []

    @discardableResult
    func append(_ request: URLRequest) -> Int {
        let index = requests.count
        requests.append(request)
        return index
    }

    func firstRequest() throws -> URLRequest {
        try XCTUnwrap(requests.first)
    }
}

enum DishesFixture {
    static func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func page(
        _ request: URLRequest, from creation: URLRequest? = nil, requestID: String? = nil,
        snapshotID: String? = nil, version: Int = 7, catalogVersion: String = "catalog-1",
        items: [[String: Any]], cursor: String? = nil, visibleTotal: Int? = nil, hiddenTotal: Int = 2,
        unknownTotal: Int = 0
    ) throws -> (Data, URLResponse) {
        let body = try body(creation ?? request)
        let createdID = try XCTUnwrap(body["request_id"] as? String)
        return try SessionFixture.response(
            request, status: creation == nil ? 201 : 200,
            body: [
                "request_id": requestID ?? createdID,
                "snapshot_id": snapshotID ?? "snapshot-\(createdID)",
                "state_version": version,
                "catalog_version": catalogVersion,
                "expires_at": "2026-11-10T12:10:00Z",
                "visibility": try XCTUnwrap(body["visibility"] as? String),
                "servings": try XCTUnwrap(body["servings"] as? Int),
                "visible_total": visibleTotal ?? items.count,
                "hidden_total": hiddenTotal,
                "unknown_total": unknownTotal,
                "items": items,
                "page": ["next_cursor": cursor as Any? ?? NSNull(), "has_more": cursor != nil]
            ],
            etag: #""state-\#(version)""#
        )
    }

    static func card(
        _ id: String, missing: Int = 0, servings: Int = 2, unknownQuantityIDs: [String] = [],
        hasMetrics: Bool = true, suitabilityUnknown: Bool = false, availabilityUnknown: Bool = false
    ) -> [String: Any] {
        let status =
            if availabilityUnknown { "unknown" } else if missing == 0 { "ready" } else { "missing" }
        let reasons: [[String: Any]] =
            suitabilityUnknown
            ? [
                [
                    "code": "allergen_data_unknown", "message": "Состав не проверен",
                    "ingredient_ids": ["cheese"], "restriction_ids": ["milk"]
                ]
            ] : []
        return [
            "id": id, "title": id, "servings": servings, "photo_url": NSNull(),
            "minutes": hasMetrics ? 15 as Any : NSNull(),
            "nutrition_per_serving": hasMetrics
                ? ["kcal": 300, "protein_g": 10, "fat_g": 12, "carbs_g": 38] as Any : NSNull(),
            "nutrition_source": NSNull(),
            "buy_cost": hasMetrics ? ["minor_units": missing == 0 ? 0 : 10000, "currency": "RUB"] as Any : NSNull(),
            "availability": [
                "status": status, "missing_count": missing, "unknown_quantity_ids": unknownQuantityIDs
            ],
            "suitability": ["status": suitabilityUnknown ? "unknown" : "allowed", "reasons": reasons],
            "allergens": ["contains": [], "completeness": "complete", "sources": []],
            "is_favorite": false,
            "methods": ["stove"]
        ]
    }
}
