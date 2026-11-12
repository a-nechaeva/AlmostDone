import Foundation
import XCTest

@testable import AlmostReady

enum RecipeFixture {
    // Canonical ID from server/data/demo_catalog.json and the server photo tests.
    static let id = "rice_tomato"
    static let detailPath = "/api/v1/recipes/\(id)"
    static let photoPath = "\(detailPath)/photo"
    static let png = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"
    )!

    @MainActor
    static func session(
        respond: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) async throws -> SessionStore {
        let session = try SessionFixture.store(storage: SessionTestStorage(.active(SessionFixture.original))) {
            request in
            if request.url?.path == "/api/v1/me/state" {
                let token = request.value(forHTTPHeaderField: "Authorization")
                let user =
                    token == "Bearer \(SessionFixture.another.accessToken)"
                    ? SessionFixture.another : SessionFixture.original
                return try SessionFixture.stateResponse(request, user: user)
            }
            return try await respond(request)
        }
        await session.restore()
        return session
    }

    @MainActor
    static func model(
        _ session: SessionStore, id: String = RecipeFixture.id, servings: Int? = nil, excludedAllergenIDs: [String] = []
    ) throws -> RecipeScreenModel {
        RecipeScreenModel(
            repository: RecipeRepository(
                session: session, account: try XCTUnwrap(session.account),
                request: RecipeRequest(id: id, servings: servings, excludedAllergenIDs: excludedAllergenIDs)
            )
        )
    }

    static func detail(
        _ request: URLRequest, id: String = RecipeFixture.id, title: String = "Рис с томатами",
        hasPhoto: Bool = true, hasEstimates: Bool = true, ready: Bool = false, defaultServings: Int = 2,
        riceRequired: Int = 300
    ) throws -> (Data, URLResponse) {
        let servings = query(request, named: "servings").first.flatMap(Int.init) ?? defaultServings
        let nutrition: [String: Double] =
            ready
            ? ["kcal": 0, "protein_g": 0, "fat_g": 0, "carbs_g": 0]
            : ["kcal": 300.5, "protein_g": 10, "fat_g": 0, "carbs_g": 38.25]
        let nullable = NSNull()
        let photoURL = "https://example.test/api/v1/recipes/\(id)/photo"
        let buyCost: [String: Any] = ["minor_units": ready ? 0 : 10_050, "currency": "RUB"]

        let card: [String: Any] = [
            "id": id,
            "title": title,
            "photo_url": hasPhoto ? photoURL as Any : nullable,
            "servings": servings,
            "minutes": ready ? nullable as Any : 25,
            "nutrition_per_serving": hasEstimates ? nutrition as Any : nullable,
            "nutrition_source": nullable,
            "buy_cost": hasEstimates ? buyCost as Any : nullable,
            "availability": [
                "status": ready ? "ready" : "missing",
                "missing_count": ready ? 0 : 1,
                "unknown_quantity_ids": ["tomato"]
            ] as [String: Any],
            "allergens": [
                "contains": ready ? [] : ["milk"],
                "completeness": ready ? "unknown" : "incomplete",
                "sources": [String]()
            ] as [String: Any],
            "suitability": [
                "status": "allowed",
                "reasons": ready
                    ? []
                    : [
                        [
                            "code": "skip_optional", "message": "Исключите необязательный ингредиент",
                            "ingredient_ids": ["cheese"], "restriction_ids": ["milk"]
                        ] as [String: Any]
                    ]
            ] as [String: Any],
            "is_favorite": false,
            "methods": ["stove"]
        ]
        let ingredients: [[String: Any]] = [
            [
                "ingredient_id": "rice", "name": "Рис",
                "required": ["value": riceRequired, "unit": "g"] as [String: Any],
                "available": ["value": ready ? riceRequired : 100, "unit": "g"] as [String: Any],
                "shortage": ["value": ready ? 0 : riceRequired - 100, "unit": "g"] as [String: Any],
                "availability": ready ? "enough" : "missing", "optional": false,
                "original_amount": "100 г", "offer": nullable
            ],
            [
                "ingredient_id": "tomato", "name": "Томаты",
                "required": ["value": 2, "unit": "pcs"] as [String: Any], "available": nullable,
                "shortage": ["value": 0, "unit": "pcs"] as [String: Any], "availability": "enough",
                "optional": false, "original_amount": nullable, "offer": nullable
            ],
            [
                "ingredient_id": "cheese", "name": "Сыр",
                "required": nullable, "available": nullable, "shortage": nullable, "availability": "optional",
                "optional": true, "original_amount": "50 г", "offer": nullable
            ],
            [
                "ingredient_id": "herbs", "name": "Зелень",
                "required": nullable, "available": nullable, "shortage": nullable, "availability": "optional",
                "optional": true, "original_amount": nullable, "offer": nullable
            ]
        ]
        let steps: [[String: Any]] = [
            ["number": 1, "text": "Промойте рис.", "minutes": nullable],
            ["number": 2, "text": "Добавьте томаты.", "minutes": 0]
        ]
        let shoppingItems: [[String: Any]] =
            ready
            ? []
            : [
                [
                    "key": "rice:rice-default", "ingredient_id": "rice", "package_id": "rice-default", "name": "Рис",
                    "package_quantity": ["value": 500, "unit": "g"] as [String: Any],
                    "package_count": 1, "total_price": buyCost
                ]
            ]
        return try SessionFixture.response(
            request,
            body: [
                "state_version": 7,
                "catalog_version": "fixture-catalog",
                "recipe": card,
                "ingredients": ingredients,
                "steps": steps,
                "shopping_items": shoppingItems
            ],
            etag: #""state-7""#
        )
    }

    static func query(_ request: URLRequest, named name: String) -> [String] {
        let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
        return items.filter { $0.name == name }.compactMap(\.value)
    }

    static func photo(
        _ request: URLRequest, contentType: String = "image/png", bytes: Data = png
    ) throws -> (Data, URLResponse) {
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: XCTUnwrap(request.url), statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": contentType]
            )
        )
        return (bytes, response)
    }
}
