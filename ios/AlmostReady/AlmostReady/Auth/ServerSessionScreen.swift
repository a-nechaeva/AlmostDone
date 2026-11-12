import Accessibility
import SwiftUI

struct ServerSessionScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                introduction
                    .padding(.horizontal, 8)

                actions
                    .padding(.top, 46)

                Text("Ваши продукты и настройки будут доступны после входа.")
                    .font(LoginTypography.regular(12, relativeTo: .caption))
                    .foregroundStyle(secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.top, 40)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 480, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.demoBackground).ignoresSafeArea())
        .task { await session.restore() }
        .onChange(of: session.phase) { previous, current in
            switch (previous, current) {
            case (_, .signingIn):
                AccessibilityNotification.Announcement("Выполняем вход").post()
            case (.signingIn, .signedOut(let notice?)):
                AccessibilityNotification.Announcement(message(for: notice)).post()
            default:
                break
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 0) {
            let brandLayout =
                dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 12))
            brandLayout {
                Image(.loginBowl)
                    .renderingMode(.template)
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)

                Text("почти готово")
                    .font(LoginTypography.bold(28, relativeTo: .title2))
            }
            .padding(.leading, 4)

            Text("Вкусное уже\nпочти дома")
                .font(LoginTypography.bold(36, relativeTo: .largeTitle))
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 52)

            Text("Войдите, чтобы сохранить продукты, ограничения и любимые блюда.")
                .font(LoginTypography.regular(15, relativeTo: .body))
                .foregroundStyle(secondaryText)
                .padding(.top, 20)
        }
        .foregroundStyle(colorScheme == .dark ? Color.white : Color(red: 32 / 255, green: 32 / 255, blue: 30 / 255))
    }

    @ViewBuilder
    private var actions: some View {
        switch session.phase {
        case .starting, .restoring:
            ProgressView("Восстанавливаем сессию")
                .tint(accent)
        case .restoreFailed:
            VStack(alignment: .leading, spacing: 14) {
                noticeText("Не удалось восстановить сессию.")
                Button("Повторить") { Task { await session.restore() } }
                    .buttonStyle(actionStyle)
                logoutButton
            }
        case .signedOut, .signingIn:
            VStack(alignment: .leading, spacing: 14) {
                if case .signedOut(let notice?) = session.phase {
                    noticeText(message(for: notice))
                }
                signInButton(isSigningIn: session.phase == .signingIn)
            }
        case .signedIn:
            logoutButton
        case .signingOut:
            ProgressView("Завершаем сессию")
                .tint(accent)
        }
    }

    private func signInButton(isSigningIn: Bool) -> some View {
        Button {
            Task { await session.signIn() }
        } label: {
            HStack(spacing: 8) {
                if isSigningIn {
                    ProgressView()
                        .tint(colorScheme == .dark ? .black : .white)
                        .accessibilityHidden(true)
                }
                Text(isSigningIn ? "Выполняем вход" : "Войти через Яндекс ID")
            }
        }
        .buttonStyle(actionStyle)
        .disabled(isSigningIn)
        .accessibilityIdentifier("auth.signIn")
    }

    private var logoutButton: some View {
        Button("Выйти", role: .destructive) {
            Task {
                // The store publishes a notice if local deletion or revocation fails.
                _ = try? await session.signOut()
            }
        }
        .font(LoginTypography.bold(14, relativeTo: .callout))
        .tint(accent)
        .controlSize(.large)
        .buttonStyle(.bordered)
    }

    private func noticeText(_ message: String) -> some View {
        Text(message)
            .font(LoginTypography.regular(13, relativeTo: .footnote))
            .foregroundStyle(
                colorScheme == .dark
                    ? Color(red: 1, green: 172 / 255, blue: 156 / 255)
                    : Color(red: 167 / 255, green: 53 / 255, blue: 45 / 255)
            )
            .padding(.horizontal, 8)
    }

    private func message(for notice: SessionStore.Notice) -> String {
        switch notice {
        case .signInFailed: "Не удалось войти через Яндекс ID. Попробуйте ещё раз."
        case .signInRequired: "Сессия завершилась. Войдите снова."
        case .storageUnavailable: "Не удалось изменить данные в Связке ключей."
        case .revocationUnconfirmed: "Вы вышли на этом устройстве. Сервер не подтвердил отзыв сессии."
        }
    }

    private var accent: Color {
        colorScheme == .dark
            ? Color(red: 1, green: 163 / 255, blue: 133 / 255)
            : Color(red: 182 / 255, green: 76 / 255, blue: 53 / 255)
    }

    private var secondaryText: Color {
        colorScheme == .dark
            ? Color(red: 189 / 255, green: 184 / 255, blue: 174 / 255)
            : Color(red: 108 / 255, green: 107 / 255, blue: 102 / 255)
    }

    private var actionStyle: LoginActionStyle {
        LoginActionStyle(background: accent, foreground: colorScheme == .dark ? .black : .white)
    }
}

private struct LoginActionStyle: ButtonStyle {
    let background: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LoginTypography.bold(14, relativeTo: .callout))
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(background, in: .rect(cornerRadius: 16))
            .contentShape(.rect(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
