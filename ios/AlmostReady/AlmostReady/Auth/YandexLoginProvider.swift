import AuthenticationServices
import Foundation
import UIKit
import YandexLoginSDK

@MainActor
final class YandexLoginProvider: YandexAuthorizing {
    private let clientID: String
    private var observer: LoginObserver?
    private var attemptID: UUID?
    private var continuation: CheckedContinuation<String, Error>?

    init(clientID: String) {
        self.clientID = clientID
    }

    func oauthToken() async throws -> String {
        guard continuation == nil, let presenter = presenter() else {
            throw YandexAuthorizationError.unavailable
        }
        let sdk = YandexLoginSDK.shared
        do {
            try sdk.activate(with: clientID, authorizationStrategy: .webOnly)
            // Explicit sign-in must not silently reuse an OAuth token from an earlier account.
            try sdk.logout()
        } catch {
            throw YandexAuthorizationError.unavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let id = UUID()
            attemptID = id
            let observer = LoginObserver { [weak self] result in
                // The SDK notifies observers under its synchronization queue.
                Task { @MainActor in self?.finish(result, id: id) }
            }
            self.observer = observer
            sdk.add(observer: observer)
            do {
                try sdk.authorize(with: presenter, authorizationStrategy: .webOnly, webAuthorizationMethod: .system)
            } catch {
                finish(.failure(.unavailable), id: id)
            }
        }
    }

    private func finish(_ result: Result<String, YandexAuthorizationError>, id: UUID) {
        guard attemptID == id, let observer, let continuation else { return }
        attemptID = nil
        self.observer = nil
        self.continuation = nil
        let sdk = YandexLoginSDK.shared
        sdk.remove(observer: observer)
        do {
            try sdk.logout()
            continuation.resume(with: result)
        } catch {
            continuation.resume(throwing: YandexAuthorizationError.unavailable)
        }
    }

    private func presenter() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }.flatMap(\.windows)
        guard var controller = windows.first(where: \.isKeyWindow)?.rootViewController else { return nil }
        while let presented = controller.presentedViewController { controller = presented }
        return controller
    }
}

nonisolated private final class LoginObserver: YandexLoginSDKObserver {
    private let finish: @Sendable (Result<String, YandexAuthorizationError>) -> Void

    init(finish: @escaping @Sendable (Result<String, YandexAuthorizationError>) -> Void) {
        self.finish = finish
    }

    func didFinishLogin(with result: Result<LoginResult, any Error>) {
        switch result {
        case .success(let login):
            finish(.success(login.token))
        case .failure(let error):
            let webError = error as? ASWebAuthenticationSessionError
            finish(.failure(webError?.code == .canceledLogin ? .cancelled : .unavailable))
        }
    }
}
