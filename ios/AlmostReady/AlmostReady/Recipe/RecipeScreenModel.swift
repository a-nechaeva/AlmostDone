import Foundation
import Observation
import UIKit

enum RecipePhoto {
    case loading
    case unavailable
    case image(UIImage)

    init(response: APIResponse<Data>) {
        let mimeType = response.metadata.contentType?.split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespaces).lowercased()
        switch mimeType {
        case "image/jpeg", "image/png", "image/webp":
            self = UIImage(data: response.value).map(Self.image) ?? .unavailable
        default:
            self = .unavailable
        }
    }
}

@MainActor
@Observable
final class RecipeScreenModel {
    enum State {
        case loading
        case notFound
        case failed(retryAfter: Date?)
        case loaded(RecipePresentation)
    }

    enum ServingsUpdate {
        case loading(Int)
        case failed(Int, retryAfter: Date?)

        var servings: Int {
            switch self {
            case .loading(let servings), .failed(let servings, _): servings
            }
        }

        var retryAfter: Date? {
            if case .failed(_, let retryAfter) = self { return retryAfter }
            return nil
        }
    }

    private let repository: RecipeRepository
    private(set) var state: State = .loading
    private(set) var attempt = 0
    private(set) var servingsUpdate: ServingsUpdate?
    private(set) var photoURL: String?
    private(set) var photo: RecipePhoto = .unavailable
    private(set) var ingredientNutrition: [String: IngredientNutrition] = [:]

    init(repository: RecipeRepository) {
        self.repository = repository
    }

    var selectedServings: Int? {
        guard case .loaded(let recipe) = state else { return nil }
        return servingsUpdate?.servings ?? recipe.servings?.count
    }

    func changeServings(by delta: Int) {
        guard repository.session.isCurrent(repository.account), let selectedServings,
            Self.canRetry(after: servingsUpdate?.retryAfter)
        else { return }
        let servings = selectedServings + delta
        guard servings != selectedServings, RecipeRequest.servingsRange.contains(servings) else { return }
        servingsUpdate = .loading(servings)
        attempt += 1
    }

    func retry() {
        guard repository.session.isCurrent(repository.account) else { return }
        if case .failed(let retryAfter) = state, Self.canRetry(after: retryAfter) {
            state = .loading
        } else if case .failed(let servings, let retryAfter) = servingsUpdate, Self.canRetry(after: retryAfter) {
            servingsUpdate = .loading(servings)
        } else {
            return
        }
        attempt += 1
    }

    func load(attempt: Int) async {
        guard canApplyResult, attempt == self.attempt else { return }

        let updatedServings: Int?
        switch state {
        case .loading:
            updatedServings = nil
        case .loaded:
            guard case .loading(let selected) = servingsUpdate else { return }
            updatedServings = selected
        case .notFound, .failed:
            return
        }

        do {
            let detail = try await repository.detail(servings: updatedServings ?? repository.request.servings)
            guard canApplyResult, attempt == self.attempt else { return }
            state = .loaded(RecipePresentation(detail: detail))
            servingsUpdate = nil
            if photoURL != detail.recipe.photoURL {
                photoURL = detail.recipe.photoURL
                photo = photoURL == nil ? .unavailable : .loading
            }
        } catch {
            guard canApplyResult, attempt == self.attempt else { return }
            let metadata = (error as? APIClientError)?.metadata
            let retryAfter = Self.retryDate(error, metadata: metadata)
            if let updatedServings {
                servingsUpdate = .failed(updatedServings, retryAfter: retryAfter)
            } else {
                state = metadata?.statusCode == 404 ? .notFound : .failed(retryAfter: retryAfter)
            }
        }
    }

    func loadIngredientNutrition() async {
        guard canApplyResult, case .loaded(let presentation) = state, !presentation.ingredients.isEmpty else { return }
        let session = repository.session
        let catalog = session.ingredientNutritionCatalog
        await catalog.load(session: session, account: repository.account)?.value
        guard canApplyResult else { return }
        ingredientNutrition = catalog.values
    }

    func loadPhoto(for url: String?) async {
        guard let url, canApplyResult, url == photoURL, case .loading = photo else { return }
        do {
            // Keep the request on the configured API origin. Photo completion only updates the photo.
            let response = try await repository.photo()
            guard canApplyResult, url == photoURL else { return }
            photo = RecipePhoto(response: response)
        } catch {
            guard canApplyResult, url == photoURL else { return }
            photo = .unavailable
        }
    }

    private var canApplyResult: Bool {
        !Task.isCancelled && repository.session.isCurrent(repository.account)
    }

    private static func canRetry(after date: Date?) -> Bool {
        date.map { $0 <= .now } ?? true
    }

    private static func retryDate(_ error: Error, metadata: HTTPResponseMetadata?) -> Date? {
        if case SessionError.refreshRateLimited(let until) = error { return until }
        guard let value = metadata?.retryAfter, let seconds = Int(value), seconds > 0 else { return nil }
        return .now.addingTimeInterval(TimeInterval(seconds))
    }
}
