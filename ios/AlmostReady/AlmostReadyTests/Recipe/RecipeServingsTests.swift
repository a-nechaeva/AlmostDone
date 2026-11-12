import Foundation
import XCTest

@testable import AlmostReady

final class RecipeServingsTests: XCTestCase {
    @MainActor
    func testUsesServerDefaultAndAppliesOnlyConfirmedDetails() async throws {
        let started = expectation(description: "Five servings requested")
        let gate = SessionResponseGate()
        let session = try await RecipeFixture.session { request in
            XCTAssertEqual(request.url?.path, RecipeFixture.detailPath)
            try SessionFixture.assertRequest(request, method: "GET", token: SessionFixture.original.accessToken)
            let servings = RecipeFixture.query(request, named: "servings")
            if servings.isEmpty {
                return try RecipeFixture.detail(request, hasPhoto: false, ready: true, defaultServings: 4)
            }
            XCTAssertEqual(servings, ["5"])
            started.fulfill()
            await gate.wait()
            return try RecipeFixture.detail(request, hasPhoto: false, riceRequired: 480)
        }

        let model = try RecipeFixture.model(session)
        await model.load(attempt: model.attempt)
        XCTAssertEqual(model.selectedServings, 4)

        model.changeServings(by: 1)
        let update = Task { [attempt = model.attempt] in await model.load(attempt: attempt) }
        await fulfillment(of: [started], timeout: 5)
        let whileLoading = model.state
        let pending = model.servingsUpdate
        XCTAssertEqual(model.selectedServings, 5)
        await gate.open()
        await update.value

        guard case .loaded(let previous) = whileLoading, case .loading(5) = pending else {
            return XCTFail("Expected confirmed details during the update")
        }
        XCTAssertEqual(previous.servings?.count, 4)
        XCTAssertEqual(previous.ingredients.first?.amount, "300 г")
        XCTAssertEqual(previous.availability.label, "Все продукты есть")
        XCTAssertEqual(previous.cost, shoppingRubles(0))
        XCTAssertTrue(previous.purchases.isEmpty)

        let recipe = try confirmedRecipe(model)
        XCTAssertEqual(recipe.servings?.count, 5)
        XCTAssertEqual(model.selectedServings, 5)
        XCTAssertNil(model.servingsUpdate)
        XCTAssertEqual(recipe.ingredients.first?.amount, "480 г")
        XCTAssertEqual(recipe.ingredients.first?.status, "Дома 100 г. Нужно докупить 380 г")
        XCTAssertEqual(recipe.availability.label, "Нужно докупить 1 продукт")
        XCTAssertEqual(recipe.cost, shoppingRubles(Decimal(100.5)))
        XCTAssertEqual(recipe.purchases.first?.packages, "1 × 500 г")
        XCTAssertEqual(recipe.minutes, 25)
        XCTAssertEqual(recipe.nutrition?.kilocalories, "300,5")
    }

    @MainActor
    func testNavigationServingsRespectBothBounds() async throws {
        for (boundary, outward) in [(1, -1), (12, 1)] {
            let requests = SessionRequestRecorder()
            let session = try await RecipeFixture.session { request in
                XCTAssertEqual(request.url?.path, RecipeFixture.detailPath)
                let servings = await requests.paths.isEmpty ? boundary : boundary - outward
                XCTAssertEqual(RecipeFixture.query(request, named: "servings"), [String(servings)])
                await requests.append(request)
                return try RecipeFixture.detail(request, hasPhoto: false)
            }
            let model = try RecipeFixture.model(session, servings: boundary)
            await model.load(attempt: model.attempt)
            XCTAssertEqual(model.selectedServings, boundary)
            XCTAssertEqual(try confirmedRecipe(model).servings?.count, boundary)

            let initialAttempt = model.attempt
            model.changeServings(by: outward)
            XCTAssertEqual(model.attempt, initialAttempt)
            XCTAssertEqual(model.selectedServings, boundary)
            XCTAssertNil(model.servingsUpdate)
            await model.load(attempt: model.attempt)

            model.changeServings(by: -outward)
            await model.load(attempt: model.attempt)
            XCTAssertEqual(try confirmedRecipe(model).servings?.count, boundary - outward)
            let paths = await requests.paths
            XCTAssertEqual(paths, [RecipeFixture.detailPath, RecipeFixture.detailPath])
        }
    }

    @MainActor
    func testUpdateFailureKeepsRecipeAndRetryRepeatsSelectedRequest() async throws {
        let requests = SessionRequestRecorder()
        let session = try await RecipeFixture.session { request in
            XCTAssertEqual(request.url?.path, RecipeFixture.detailPath)
            try SessionFixture.assertRequest(request, method: "GET", token: SessionFixture.original.accessToken)
            XCTAssertEqual(RecipeFixture.query(request, named: "exclude_allergens"), ["eggs", "soy"])
            await requests.append(request)
            let count = await requests.paths.count
            XCTAssertEqual(RecipeFixture.query(request, named: "servings"), count == 1 ? ["6"] : ["7"])
            if count == 2 {
                return try SessionFixture.error(request, status: 503, code: "service_unavailable")
            }
            return try RecipeFixture.detail(request, hasPhoto: false, riceRequired: count == 1 ? 300 : 590)
        }

        let model = try RecipeFixture.model(session, servings: 6, excludedAllergenIDs: ["eggs", "soy"])
        await model.load(attempt: model.attempt)
        model.changeServings(by: 1)
        await model.load(attempt: model.attempt)

        guard case .failed(7, retryAfter: nil) = model.servingsUpdate else {
            return XCTFail("Expected the selected request to be retryable")
        }
        XCTAssertEqual(model.selectedServings, 7)
        XCTAssertEqual(try confirmedRecipe(model).servings?.count, 6)
        XCTAssertEqual(try confirmedRecipe(model).ingredients.first?.amount, "300 г")

        model.retry()
        await model.load(attempt: model.attempt)
        XCTAssertNil(model.servingsUpdate)
        XCTAssertEqual(try confirmedRecipe(model).servings?.count, 7)
        XCTAssertEqual(try confirmedRecipe(model).ingredients.first?.amount, "590 г")
        let paths = await requests.paths
        XCTAssertEqual(paths.count, 3)
    }

    @MainActor
    func testInitialAndUpdateRetriesRespectRetryAfter() async throws {
        for initialFailure in [true, false] {
            let session = try await RecipeFixture.session { request in
                XCTAssertEqual(request.url?.path, RecipeFixture.detailPath)
                let servings = RecipeFixture.query(request, named: "servings")
                if !initialFailure && servings == ["6"] {
                    return try RecipeFixture.detail(request, hasPhoto: false)
                }
                XCTAssertEqual(servings, initialFailure ? ["6"] : ["7"])
                return try SessionFixture.error(request, status: 429, code: "rate_limited", retryAfter: "120")
            }
            let model = try RecipeFixture.model(session, servings: 6)
            await model.load(attempt: model.attempt)
            if initialFailure {
                guard case .failed(let retryAfter) = model.state else { return XCTFail("Expected initial failure") }
                XCTAssertGreaterThan(try XCTUnwrap(retryAfter), .now)
            } else {
                model.changeServings(by: 1)
                await model.load(attempt: model.attempt)
                XCTAssertGreaterThan(try XCTUnwrap(model.servingsUpdate?.retryAfter), .now)
                XCTAssertEqual(try confirmedRecipe(model).servings?.count, 6)
            }

            let failedAttempt = model.attempt
            model.retry()
            model.changeServings(by: 1)
            XCTAssertEqual(model.attempt, failedAttempt)
        }
    }

    @MainActor
    func testLateDetailsAndPhotoCannotRestoreOldIngredients() async throws {
        let staleStarted = expectation(description: "Three servings requested")
        let photoStarted = expectation(description: "Recipe photo requested")
        let staleGate = SessionResponseGate()
        let photoGate = SessionResponseGate()
        let session = try await RecipeFixture.session { request in
            switch request.url?.path {
            case RecipeFixture.detailPath:
                switch RecipeFixture.query(request, named: "servings") {
                case []: return try RecipeFixture.detail(request)
                case ["3"]:
                    staleStarted.fulfill()
                    await staleGate.wait()
                    return try RecipeFixture.detail(request, riceRequired: 400)
                case ["4"]: return try RecipeFixture.detail(request, riceRequired: 520)
                default: throw URLError(.unsupportedURL)
                }
            case RecipeFixture.photoPath:
                photoStarted.fulfill()
                await photoGate.wait()
                return try RecipeFixture.photo(request)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let model = try RecipeFixture.model(session)
        await model.load(attempt: model.attempt)
        let photo = Task { await model.loadPhoto(for: model.photoURL) }
        await fulfillment(of: [photoStarted], timeout: 5)

        model.changeServings(by: 1)
        let stale = Task { [attempt = model.attempt] in await model.load(attempt: attempt) }
        await fulfillment(of: [staleStarted], timeout: 5)
        model.changeServings(by: 1)
        XCTAssertEqual(model.selectedServings, 4)
        await model.load(attempt: model.attempt)
        await staleGate.open()
        await stale.value
        let afterStaleUpdate = model.state
        await photoGate.open()
        await photo.value

        guard case .loaded(let current) = afterStaleUpdate, case .image = model.photo else {
            return XCTFail("Expected the latest recipe and the photo")
        }
        XCTAssertEqual(current.servings?.count, 4)
        XCTAssertEqual(current.ingredients.first?.amount, "520 г")
        XCTAssertEqual(try confirmedRecipe(model).servings?.count, 4)
        XCTAssertEqual(try confirmedRecipe(model).ingredients.first?.amount, "520 г")
    }

    @MainActor
    func testCancelledUpdateKeepsConfirmedRecipe() async throws {
        let started = expectation(description: "Update requested before cancellation")
        let gate = SessionResponseGate()
        let session = try await RecipeFixture.session { request in
            XCTAssertEqual(request.url?.path, RecipeFixture.detailPath)
            if !RecipeFixture.query(request, named: "servings").isEmpty {
                started.fulfill()
                await gate.wait()
            }
            return try RecipeFixture.detail(request, hasPhoto: false)
        }

        let model = try RecipeFixture.model(session)
        await model.load(attempt: model.attempt)
        model.changeServings(by: 1)
        let update = Task { [attempt = model.attempt] in await model.load(attempt: attempt) }
        await fulfillment(of: [started], timeout: 5)
        update.cancel()
        await gate.open()
        await update.value

        XCTAssertEqual(try confirmedRecipe(model).servings?.count, 2)
        guard case .loading(3) = model.servingsUpdate else { return XCTFail("Expected the pending selection") }
    }

    @MainActor
    func testOldAccountUpdateCannotApplyAfterSignIn() async throws {
        let started = expectation(description: "Old account update requested")
        let gate = SessionResponseGate()
        let session = try await RecipeFixture.session { request in
            switch request.url?.path {
            case RecipeFixture.detailPath:
                switch RecipeFixture.query(request, named: "servings") {
                case []:
                    try SessionFixture.assertRequest(request, method: "GET", token: SessionFixture.original.accessToken)
                    return try RecipeFixture.detail(request, hasPhoto: false)
                case ["3"]:
                    try SessionFixture.assertRequest(request, method: "GET", token: SessionFixture.original.accessToken)
                    started.fulfill()
                    await gate.wait()
                    return try RecipeFixture.detail(request, hasPhoto: false, riceRequired: 420)
                case ["5"]:
                    try SessionFixture.assertRequest(request, method: "GET", token: SessionFixture.another.accessToken)
                    return try RecipeFixture.detail(request, hasPhoto: false, riceRequired: 550)
                default:
                    throw URLError(.unsupportedURL)
                }
            case "/api/v1/auth/logout":
                return try SessionFixture.response(request, status: 204)
            case "/api/v1/auth/yandex":
                return try SessionFixture.sessionResponse(request, SessionFixture.another)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let original = try RecipeFixture.model(session)
        await original.load(attempt: original.attempt)
        original.changeServings(by: 1)
        let update = Task { [attempt = original.attempt] in await original.load(attempt: attempt) }
        await fulfillment(of: [started], timeout: 5)
        do {
            _ = try await session.signOut()
        } catch {
            await gate.open()
            await update.value
            throw error
        }
        await session.signIn()
        await gate.open()
        await update.value
        XCTAssertEqual(try confirmedRecipe(original).servings?.count, 2)

        let current = try RecipeFixture.model(session, servings: 5)
        await current.load(attempt: current.attempt)
        XCTAssertEqual(try confirmedRecipe(current).servings?.count, 5)
        XCTAssertEqual(try confirmedRecipe(current).ingredients.first?.amount, "550 г")
    }

    @MainActor
    private func confirmedRecipe(
        _ model: RecipeScreenModel, file: StaticString = #filePath, line: UInt = #line
    ) throws -> RecipePresentation {
        let recipe: RecipePresentation?
        if case .loaded(let presentation) = model.state {
            recipe = presentation
        } else {
            recipe = nil
        }
        return try XCTUnwrap(recipe, "Expected confirmed recipe details", file: file, line: line)
    }
}
