import Foundation
import UIKit
import XCTest

@testable import AlmostReady

final class RecipeScreenTests: XCTestCase {
    @MainActor
    func testCanonicalRecipeUsesSessionAndPresentsDetailsBeforePublicPhotoArrives() async throws {
        let photoStarted = expectation(description: "Public photo requested")
        let photoGate = SessionResponseGate()
        let session = try await RecipeFixture.session { request in
            switch request.url?.path {
            case RecipeFixture.detailPath:
                try SessionFixture.assertRequest(request, method: "GET", token: SessionFixture.original.accessToken)
                let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
                XCTAssertEqual(query?.filter { $0.name == "servings" }.compactMap(\.value), ["6"])
                XCTAssertEqual(query?.filter { $0.name == "exclude_allergens" }.compactMap(\.value), ["eggs", "soy"])
                return try RecipeFixture.detail(request)
            case RecipeFixture.photoPath:
                try SessionFixture.assertRequest(request, method: "GET")
                XCTAssertEqual(request.url?.absoluteString, "https://example.test\(RecipeFixture.photoPath)")
                photoStarted.fulfill()
                await photoGate.wait()
                return try RecipeFixture.photo(request, contentType: "Image/PNG; example=1")
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let model = try RecipeFixture.model(session, servings: 6, excludedAllergenIDs: ["eggs", "soy"])
        let load = Task { await model.load() }
        await fulfillment(of: [photoStarted], timeout: 5)
        let stateWhilePhotoIsLoading = model.state
        await photoGate.open()
        await load.value
        guard case .loaded(let recipe, .loading) = stateWhilePhotoIsLoading else {
            return XCTFail("Expected the recipe while the photo is loading")
        }

        XCTAssertEqual(recipe.title, "Рис с томатами")
        XCTAssertEqual(recipe.minutes, 25)
        XCTAssertEqual(recipe.servings?.count, 6)
        XCTAssertEqual(recipe.nutrition?.kilocalories, "300,5")
        XCTAssertEqual(recipe.nutrition?.macros, "Б 10 г · Ж 0 г · У 38,25 г")
        XCTAssertEqual(recipe.allergens, ["Молочный белок"])
        XCTAssertEqual(recipe.allergenNote, "Сведения об аллергенах неполные")
        XCTAssertEqual(recipe.suitabilityNotes, ["Исключите необязательный ингредиент"])
        XCTAssertEqual(recipe.availability.label, "Нужно докупить 1 продукт")
        XCTAssertEqual(recipe.ingredients.map(\.name), ["Рис", "Томаты", "Сыр", "Зелень"])
        let rice = try XCTUnwrap(recipe.ingredients.first { $0.id == "rice" })
        XCTAssertEqual(rice.amount, "300 г")
        XCTAssertEqual(rice.status, "Дома 100 г. Нужно докупить 200 г")
        XCTAssertEqual(recipe.ingredients.first { $0.id == "tomato" }?.status, "Есть дома, количество неизвестно")
        let cheese = try XCTUnwrap(recipe.ingredients.first { $0.id == "cheese" })
        XCTAssertEqual(cheese.status, "По желанию. Лучше исключить")
        XCTAssertNil(cheese.amount)
        XCTAssertEqual(cheese.originalAmountNote, "50 г (в исходном рецепте)")
        XCTAssertEqual(recipe.ingredients.first { $0.id == "herbs" }?.status, "По желанию")
        XCTAssertEqual(recipe.steps.map(\.number), [1, 2])
        XCTAssertEqual(recipe.steps.first?.text, "Промойте рис.")
        XCTAssertEqual(recipe.steps.last?.minutes, 0)
        XCTAssertEqual(recipe.purchases.first?.packages, "1 × 500 г")
        XCTAssertEqual(recipe.purchases.first?.price, shoppingRubles(Decimal(100.5)))
        XCTAssertEqual(recipe.cost, shoppingRubles(Decimal(100.5)))

        guard case .loaded(_, .image(let image)) = model.state else { return XCTFail("Expected decoded photo") }
        XCTAssertEqual(image.size.width, 1)
        XCTAssertEqual(image.size.height, 1)
    }

    @MainActor
    func testAbsentPhotoAndUnknownEstimatesDifferFromZero() async throws {
        for hasEstimates in [false, true] {
            let session = try await RecipeFixture.session { request in
                XCTAssertEqual(request.url?.path, RecipeFixture.detailPath)
                XCTAssertNil(request.url?.query)
                return try RecipeFixture.detail(request, hasPhoto: false, hasEstimates: hasEstimates, ready: true)
            }
            let model = try RecipeFixture.model(session)
            await model.load()
            guard case .loaded(let recipe, .unavailable) = model.state else {
                return XCTFail("Expected a recipe with a local placeholder")
            }
            XCTAssertNil(recipe.minutes)
            XCTAssertEqual(recipe.availability.label, "Все продукты есть")
            XCTAssertEqual(recipe.cost, hasEstimates ? shoppingRubles(0) : "Цена неизвестна")
            XCTAssertEqual(recipe.nutrition?.kilocalories, hasEstimates ? "0" : nil)
            XCTAssertEqual(recipe.allergenNote, "Сведения об аллергенах неизвестны")
        }
    }

    @MainActor
    func testPhoto404And503KeepRecipeWithPlaceholder() async throws {
        for status in [404, 503] {
            let session = try await RecipeFixture.session { request in
                switch request.url?.path {
                case RecipeFixture.detailPath:
                    return try RecipeFixture.detail(request)
                case RecipeFixture.photoPath:
                    try SessionFixture.assertRequest(request, method: "GET")
                    return try SessionFixture.error(
                        request, status: status, code: status == 404 ? "not_found" : "service_unavailable")
                default:
                    throw URLError(.unsupportedURL)
                }
            }
            try await assertRecipeWithPlaceholder(session)
        }
    }

    @MainActor
    func testCorruptPhotoAndUnsupportedMediaTypeKeepRecipeWithPlaceholder() async throws {
        for (contentType, bytes) in [("image/png", Data("corrupt image".utf8)), ("text/html", RecipeFixture.png)] {
            let session = try await RecipeFixture.session { request in
                switch request.url?.path {
                case RecipeFixture.detailPath:
                    return try RecipeFixture.detail(request)
                case RecipeFixture.photoPath:
                    return try RecipeFixture.photo(request, contentType: contentType, bytes: bytes)
                default:
                    throw URLError(.unsupportedURL)
                }
            }
            try await assertRecipeWithPlaceholder(session)
        }
    }

    @MainActor
    func testPhotoCancelledByTransportKeepsRecipeWithPlaceholder() async throws {
        let session = try await RecipeFixture.session { request in
            switch request.url?.path {
            case RecipeFixture.detailPath:
                return try RecipeFixture.detail(request)
            case RecipeFixture.photoPath:
                throw URLError(.cancelled)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        try await assertRecipeWithPlaceholder(session)
    }

    @MainActor
    func testMissingRecipeShowsNotFoundWithoutRequestingPhoto() async throws {
        let session = try await RecipeFixture.session { request in
            XCTAssertEqual(request.url?.path, RecipeFixture.detailPath)
            try SessionFixture.assertRequest(request, method: "GET", token: SessionFixture.original.accessToken)
            return try SessionFixture.error(request, status: 404, code: "not_found")
        }
        let model = try RecipeFixture.model(session)
        await model.load()
        guard case .notFound = model.state else { return XCTFail("Expected recipe not found") }
    }

    @MainActor
    func testRecipeFailureCanBeRetried() async throws {
        for cancelledByTransport in [false, true] {
            let requests = SessionRequestRecorder()
            let session = try await RecipeFixture.session { request in
                XCTAssertEqual(request.url?.path, RecipeFixture.detailPath)
                await requests.append(request)
                if await requests.paths.count == 1 {
                    if cancelledByTransport { throw URLError(.cancelled) }
                    return try SessionFixture.error(request, status: 503, code: "service_unavailable")
                }
                return try RecipeFixture.detail(request, hasPhoto: false)
            }
            let model = try RecipeFixture.model(session)
            await model.load()
            guard case .failed(retryAfter: nil) = model.state else { return XCTFail("Expected a retryable failure") }

            model.retry()
            XCTAssertEqual(model.attempt, 1)
            guard case .loading = model.state else { return XCTFail("Expected loading after retry") }
            await model.load()
            guard case .loaded(_, .unavailable) = model.state else { return XCTFail("Expected the retried recipe") }
        }
    }

    @MainActor
    func testCancelledDetailCannotApplyAfterOpeningAnotherRecipe() async throws {
        let firstStarted = expectation(description: "First recipe requested")
        let firstGate = SessionResponseGate()
        let session = try await RecipeFixture.session { request in
            switch request.url?.path {
            case RecipeFixture.detailPath:
                firstStarted.fulfill()
                await firstGate.wait()
                return try RecipeFixture.detail(request, hasPhoto: false)
            case "/api/v1/recipes/tomato_cheese":
                return try RecipeFixture.detail(
                    request, id: "tomato_cheese", title: "Томаты с сыром", hasPhoto: false)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let first = try RecipeFixture.model(session)
        let second = try RecipeFixture.model(session, id: "tomato_cheese")
        let load = Task { await first.load() }
        await fulfillment(of: [firstStarted], timeout: 5)
        load.cancel()
        await second.load()
        await firstGate.open()
        await load.value

        guard case .loading = first.state, case .loaded(let recipe, .unavailable) = second.state else {
            return XCTFail("Expected only the second recipe to apply")
        }
        XCTAssertEqual(recipe.title, "Томаты с сыром")
    }

    @MainActor
    func testPhotoResponseAfterAccountChangeDoesNotApply() async throws {
        let photoStarted = expectation(description: "Photo requested before sign-out")
        let photoGate = SessionResponseGate()
        let session = try await RecipeFixture.session { request in
            switch request.url?.path {
            case RecipeFixture.detailPath:
                return try RecipeFixture.detail(request)
            case RecipeFixture.photoPath:
                photoStarted.fulfill()
                await photoGate.wait()
                return try RecipeFixture.photo(request)
            case "/api/v1/auth/logout":
                return try SessionFixture.response(request, status: 204)
            case "/api/v1/auth/yandex":
                return try SessionFixture.sessionResponse(request, SessionFixture.another)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let originalAccount = try XCTUnwrap(session.account)
        let model = try RecipeFixture.model(session)
        let load = Task { await model.load() }
        await fulfillment(of: [photoStarted], timeout: 5)
        _ = try await session.signOut()
        await session.signIn()
        await photoGate.open()
        await load.value

        let newAccount = try XCTUnwrap(session.account)
        XCTAssertNotEqual(originalAccount.id, newAccount.id)
        guard case .loaded(_, .loading) = model.state else { return XCTFail("Expected the old photo to be ignored") }
    }

    @MainActor
    private func assertRecipeWithPlaceholder(_ session: SessionStore) async throws {
        let model = try RecipeFixture.model(session)
        await model.load()
        guard case .loaded(let recipe, .unavailable) = model.state else {
            return XCTFail("Expected a recipe with a local placeholder")
        }
        XCTAssertEqual(recipe.title, "Рис с томатами")
    }
}
