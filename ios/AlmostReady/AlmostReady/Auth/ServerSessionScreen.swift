import SwiftUI

struct ServerSessionScreen: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(spacing: 16) {
            Text("Подключение к серверу")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)

            switch session.phase {
            case .starting, .restoring:
                ProgressView("Восстанавливаем сессию")
            case .restoreFailed:
                Text("Не удалось восстановить сессию.")
                Button("Повторить") { Task { await session.restore() } }
                logoutButton
            case .signedOut(let notice):
                if let notice { Text(message(for: notice)) }
                Button("Войти через Яндекс ID") { Task { await session.signIn() } }
                    .buttonStyle(.borderedProminent)
            case .signingIn:
                ProgressView("Выполняем вход")
            case .signedIn:
                Text("Сессия подтверждена сервером.")
                logoutButton
            case .signingOut:
                ProgressView("Завершаем сессию")
            }
        }
        .multilineTextAlignment(.center)
        .padding()
        .task { await session.restore() }
    }

    private var logoutButton: some View {
        Button("Выйти", role: .destructive) {
            Task {
                // The store publishes a notice if local deletion or revocation fails.
                _ = try? await session.signOut()
            }
        }
    }

    private func message(for notice: SessionStore.Notice) -> LocalizedStringKey {
        switch notice {
        case .signInFailed: "Не удалось войти через Яндекс ID. Попробуйте ещё раз."
        case .signInRequired: "Сессия завершилась. Войдите снова."
        case .storageUnavailable: "Не удалось изменить данные в Связке ключей."
        case .revocationUnconfirmed: "Вы вышли на этом устройстве. Сервер не подтвердил отзыв сессии."
        }
    }
}
