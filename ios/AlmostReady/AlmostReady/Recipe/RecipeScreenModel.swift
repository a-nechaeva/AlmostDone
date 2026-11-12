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
        case loaded(RecipePresentation, RecipePhoto)
    }

    private let repository: RecipeRepository
    private(set) var state: State = .loading
    private(set) var attempt = 0

    init(repository: RecipeRepository) {
        self.repository = repository
    }

    func retry() {
        guard case .failed(let retryAfter) = state, retryAfter.map({ $0 <= .now }) ?? true else { return }
        state = .loading
        attempt += 1
    }

    func load() async {
        guard canApplyResult else { return }

        if case .loading = state {
            do {
                let detail = try await repository.detail()
                guard canApplyResult else { return }
                // The server advertises photo availability. Keep the request on the configured API origin.
                state = .loaded(
                    RecipePresentation(detail: detail), detail.recipe.photoURL == nil ? .unavailable : .loading)
            } catch {
                guard canApplyResult else { return }
                let metadata = (error as? APIClientError)?.metadata
                if metadata?.statusCode == 404 {
                    state = .notFound
                } else {
                    state = .failed(retryAfter: Self.retryDate(error, metadata: metadata))
                }
                return
            }
        }

        guard case .loaded(let presentation, .loading) = state else { return }
        do {
            let response = try await repository.photo()
            guard canApplyResult else { return }
            state = .loaded(presentation, RecipePhoto(response: response))
        } catch {
            guard canApplyResult else { return }
            state = .loaded(presentation, .unavailable)
        }
    }

    private var canApplyResult: Bool {
        !Task.isCancelled && repository.session.isCurrent(repository.account)
    }

    private static func retryDate(_ error: Error, metadata: HTTPResponseMetadata?) -> Date? {
        if case SessionError.refreshRateLimited(let until) = error { return until }
        guard let value = metadata?.retryAfter, let seconds = Int(value), seconds > 0 else { return nil }
        return .now.addingTimeInterval(TimeInterval(seconds))
    }
}
