import Foundation
import SwiftUI
import XCTest

@testable import AlmostReady

final class IngredientNutritionTests: XCTestCase {
    private static let catalogPath = "/api/v1/catalog"
    private static let pantryPath = "/api/v1/me/pantry"
    private static let searchPath = "/api/v1/ingredients"
    private static let knownLabel = "КБЖУ на 100 г · 350,5 ккал · Б 7 г · Ж 1,25 г · У 78 г"
    private static let zeroLabel = "КБЖУ на 100 г · 0 ккал · Б 0 г · Ж 0 г · У 0 г"

    @MainActor
    func testSearchUsesNutritionInSuggestionsWithoutLoadingCatalog() async throws {
        let log = SessionRequestRecorder()
        let session = try await RecipeFixture.session { request in
            await log.append(request)
            guard request.url?.path == Self.searchPath else { throw URLError(.unsupportedURL) }
            try SessionFixture.assertRequest(request, method: "GET", token: SessionFixture.original.accessToken)
            let entries = Self.ingredients + [["id": "herbs"]]
            let items = entries.map { entry in
                entry.merging(["allowed_units": ["g"], "name": "Рис"]) { _, value in value }
            }
            return try SessionFixture.response(
                request, body: ["items": items, "page": ["next_cursor": NSNull(), "has_more": false]]
            )
        }
        let model = IngredientSearchModel(repository: try repository(session))
        model.query = "Рис"
        await model.search(request: model.requestID)

        guard case .results(let results) = model.phase else { return XCTFail("Expected suggestions") }
        XCTAssertEqual(results.map(\.id), ["tomato", "cheese", "rice", "herbs"])
        assertLines(results.map(\.nutrition), expected: [Self.zeroLabel, nil, Self.knownLabel, nil])

        let withoutNutrition = try XCTUnwrap(results.first { $0.id == "cheese" })
        let baseline = rowHeight(IngredientSuggestionLabel(ingredient: withoutNutrition))
        assertRowHeights(
            results.map { rowHeight(IngredientSuggestionLabel(ingredient: $0)) },
            baseline: Array(repeating: baseline, count: results.count), showNutrition: [true, false, true, false]
        )
        let paths = await log.paths
        XCTAssertEqual(paths, [Self.searchPath])
    }

    @MainActor
    func testPantryAndRecipeJoinByIDAndShareOneCatalogRequest() async throws {
        let log = SessionRequestRecorder()
        let catalogStarted = expectation(description: "Pantry starts loading the catalog for all rows")
        let recipeStarted = expectation(description: "Recipe also requests ingredient nutrition")
        let catalogGate = SessionResponseGate()
        let session = try await RecipeFixture.session { request in
            await log.append(request)
            switch request.url?.path {
            case Self.pantryPath:
                return try Self.pantry(request)
            case RecipeFixture.detailPath:
                return try RecipeFixture.detail(request, hasPhoto: false)
            case Self.catalogPath:
                try SessionFixture.assertRequest(request, method: "GET", token: SessionFixture.original.accessToken)
                XCTAssertNil(request.url?.query)
                catalogStarted.fulfill()
                await catalogGate.wait()
                return try Self.catalog(request)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        let pantry = PantryModel(repository: try repository(session))
        let recipe = try RecipeFixture.model(session)
        await pantry.reload()
        await fulfillment(of: [catalogStarted], timeout: 5)
        await recipe.load(attempt: recipe.attempt)
        guard let items = pantry.snapshot?.items, case .loaded(let detail) = recipe.state else {
            await catalogGate.open()
            return XCTFail("Expected the pantry and recipe before the catalog response")
        }
        let pantryBaseline = items.map { rowHeight(PantryItemLabel(item: $0, model: pantry)) }

        let recipeLoad = Task {
            recipeStarted.fulfill()
            await recipe.loadIngredientNutrition()
        }
        await fulfillment(of: [recipeStarted], timeout: 5)
        await catalogGate.open()
        await recipeLoad.value
        XCTAssertEqual(items.map(\.id), ["rice", "tomato", "cheese", "herbs"])
        XCTAssertEqual(detail.ingredients.map(\.id), items.map(\.id))
        let expected = [Self.knownLabel, Self.zeroLabel, nil, nil]
        assertLines(items.map { pantry.nutrition(for: $0) }, expected: expected)
        assertLines(detail.ingredients.map { recipe.ingredientNutrition[$0.id] }, expected: expected)
        XCTAssertEqual(detail.nutrition?.kilocalories, "300,5")

        assertRowHeights(
            items.map { rowHeight(PantryItemLabel(item: $0, model: pantry)) },
            baseline: pantryBaseline, showNutrition: [true, true, false, false]
        )
        assertRowHeights(
            detail.ingredients.map {
                rowHeight(
                    RecipeIngredientRow(
                        ingredient: $0, nutrition: recipe.ingredientNutrition[$0.id],
                        readyColor: .green))
            },
            baseline: detail.ingredients.map {
                rowHeight(RecipeIngredientRow(ingredient: $0, nutrition: nil, readyColor: .green))
            },
            showNutrition: [true, true, false, false]
        )

        await pantry.reload()
        await recipe.loadIngredientNutrition()
        let paths = await log.paths
        XCTAssertEqual(paths, [Self.pantryPath, Self.catalogPath, RecipeFixture.detailPath, Self.pantryPath])
    }

    @MainActor
    func testCatalogFailureKeepsPantryAndRecipeAvailable() async throws {
        let session = try await RecipeFixture.session { request in
            switch request.url?.path {
            case Self.pantryPath:
                return try Self.pantry(request)
            case RecipeFixture.detailPath:
                return try RecipeFixture.detail(request, hasPhoto: false)
            case Self.catalogPath:
                return try SessionFixture.error(request, status: 503, code: "service_unavailable")
            default:
                throw URLError(.unsupportedURL)
            }
        }
        let pantry = PantryModel(repository: try repository(session))
        let recipe = try RecipeFixture.model(session)
        await pantry.reload()
        await recipe.load(attempt: recipe.attempt)
        await recipe.loadIngredientNutrition()

        let items = try XCTUnwrap(pantry.snapshot?.items)
        XCTAssertEqual(items.count, 4)
        XCTAssertFalse(pantry.loadFailed)
        guard case .loaded(let detail) = recipe.state else { return XCTFail("Expected the recipe") }
        XCTAssertEqual(detail.ingredients.count, 4)
        assertLines(items.map { pantry.nutrition(for: $0) }, expected: [nil, nil, nil, nil])
        assertLines(detail.ingredients.map { recipe.ingredientNutrition[$0.id] }, expected: [nil, nil, nil, nil])
    }

    @MainActor
    func testLateCatalogResponseIsIgnoredAfterAccountChange() async throws {
        let catalogStarted = expectation(description: "Catalog requested by the original account")
        let currentCatalogRequested = expectation(description: "New account requests its own catalog")
        let catalogGate = SessionResponseGate()
        let session = try await RecipeFixture.session { request in
            switch request.url?.path {
            case RecipeFixture.detailPath:
                return try RecipeFixture.detail(request, hasPhoto: false)
            case Self.catalogPath:
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer \(SessionFixture.original.accessToken)"
                {
                    catalogStarted.fulfill()
                    await catalogGate.wait()
                    return try Self.catalog(request)
                }
                try SessionFixture.assertRequest(request, method: "GET", token: SessionFixture.another.accessToken)
                currentCatalogRequested.fulfill()
                return try SessionFixture.response(request, body: ["ingredients": []])
            case "/api/v1/auth/logout":
                return try SessionFixture.response(request, status: 204)
            case "/api/v1/auth/yandex":
                return try SessionFixture.sessionResponse(request, SessionFixture.another)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        let original = try RecipeFixture.model(session)
        let originalAccount = try XCTUnwrap(session.account)
        await original.load(attempt: original.attempt)
        let pending = Task { await original.loadIngredientNutrition() }
        await fulfillment(of: [catalogStarted], timeout: 5)
        _ = try await session.signOut()
        await session.signIn()
        await catalogGate.open()
        await pending.value

        let current = try RecipeFixture.model(session)
        await current.load(attempt: current.attempt)
        await current.loadIngredientNutrition()
        await fulfillment(of: [currentCatalogRequested], timeout: 5)
        XCTAssertNotEqual(session.account?.id, originalAccount.id)
        XCTAssertTrue(original.ingredientNutrition.isEmpty)
        XCTAssertTrue(current.ingredientNutrition.isEmpty)
    }

    @MainActor
    func testCancelledRecipeDoesNotInstallLateNutrition() async throws {
        let catalogStarted = expectation(description: "Catalog requested by the original recipe screen")
        let catalogGate = SessionResponseGate()
        let nextID = "tomato_cheese"
        let session = try await RecipeFixture.session { request in
            switch request.url?.path {
            case RecipeFixture.detailPath:
                return try RecipeFixture.detail(request, hasPhoto: false)
            case "/api/v1/recipes/\(nextID)":
                return try RecipeFixture.detail(request, id: nextID, hasPhoto: false)
            case Self.catalogPath:
                catalogStarted.fulfill()
                await catalogGate.wait()
                return try Self.catalog(request)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        let original = try RecipeFixture.model(session)
        let next = try RecipeFixture.model(session, id: nextID)
        await original.load(attempt: original.attempt)
        let pending = Task { await original.loadIngredientNutrition() }
        await fulfillment(of: [catalogStarted], timeout: 5)
        pending.cancel()
        await next.load(attempt: next.attempt)
        await catalogGate.open()
        await pending.value
        await next.loadIngredientNutrition()

        XCTAssertTrue(original.ingredientNutrition.isEmpty)
        assertLines([next.ingredientNutrition["rice"]], expected: [Self.knownLabel])
    }

    @MainActor
    private func repository(_ session: SessionStore) throws -> ProductsRepository {
        ProductsRepository(session: session, account: try XCTUnwrap(session.account))
    }

    @MainActor
    private func assertLines(
        _ values: [IngredientNutrition?], expected: [String?], file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(values.map { IngredientNutritionLine(nutrition: $0).label }, expected, file: file, line: line)
    }

    @MainActor
    private func rowHeight(_ row: some View) -> CGFloat {
        let renderer = ImageRenderer(content: row)
        renderer.proposedSize = ProposedViewSize(width: 320, height: nil)
        return renderer.uiImage?.size.height ?? 0
    }

    private func assertRowHeights(
        _ heights: [CGFloat], baseline: [CGFloat], showNutrition: [Bool],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(heights.count, showNutrition.count, file: file, line: line)
        XCTAssertEqual(baseline.count, showNutrition.count, file: file, line: line)
        for ((height, original), showsLine) in zip(zip(heights, baseline), showNutrition) {
            XCTAssertGreaterThan(original, 0, file: file, line: line)
            if showsLine {
                XCTAssertGreaterThan(height, original, file: file, line: line)
            } else {
                XCTAssertEqual(height, original, file: file, line: line)
            }
        }
    }

    private static var ingredients: [[String: Any]] {
        [
            [
                "id": "tomato", "name": "Томаты",
                "nutrition_per_100g": ["kcal": 0, "protein_g": 0, "fat_g": 0, "carbs_g": 0]
            ],
            ["id": "cheese", "name": "Сыр", "nutrition_per_100g": NSNull()],
            [
                "id": "rice", "name": "Рис",
                "nutrition_per_100g": ["kcal": 350.5, "protein_g": 7, "fat_g": 1.25, "carbs_g": 78]
            ]
        ]
    }

    private static func catalog(_ request: URLRequest) throws -> (Data, URLResponse) {
        try SessionFixture.response(
            request, body: ["catalog_version": "fixture-catalog", "ingredients": ingredients, "recipes": []]
        )
    }

    private static func pantry(_ request: URLRequest) throws -> (Data, URLResponse) {
        let items: [[String: Any]] = ["rice", "tomato", "cheese", "herbs"].map {
            ["ingredient_id": $0, "name": "Продукт", "quantity": NSNull()]
        }
        return try SessionFixture.response(
            request, body: ["state_version": 7, "items": items], etag: #""state-7""#
        )
    }
}
