import SwiftUI

struct ServerProfileScreen: View {
    @State private var model: ServerProfileModel
    private let onOpenProducts: (() -> Void)?
    private let onNutritionPresentationChange: (Bool) -> Void

    init(
        repository: ProfileRepository,
        onOpenProducts: (() -> Void)?,
        onNutritionPresentationChange: @escaping (Bool) -> Void
    ) {
        _model = State(initialValue: ServerProfileModel(repository: repository))
        self.onOpenProducts = onOpenProducts
        self.onNutritionPresentationChange = onNutritionPresentationChange
    }

    var body: some View {
        ProfileHome(
            onOpenNutrition: { Task { await model.openEditor() } },
            onOpenProducts: onOpenProducts
        ) {
            account
        } actions: {
            Button(role: .destructive) {
                Task {
                    guard model.repository.session.isCurrent(model.repository.account) else { return }
                    _ = try? await model.repository.session.signOut()
                }
            } label: {
                Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("profile.signOut")
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.loadProfile() }
        .onChange(of: model.editorID != nil) { _, isPresented in
            onNutritionPresentationChange(isPresented)
        }
        .navigationDestination(isPresented: nutritionPresentation) {
            ServerProfileNutritionScreen(model: model)
                .toolbar(.visible, for: .navigationBar)
        }
    }

    @ViewBuilder private var account: some View {
        if let profile = model.profile?.value {
            if let name = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                ProfileAccountHeader(name: name)
            } else {
                ProfileAccountHeader(name: "Яндекс ID", subtitle: "ID аккаунта: \(profile.userID)")
            }
        } else if model.profileLoadFailed {
            VStack(alignment: .leading, spacing: 8) {
                Text("Не удалось загрузить профиль")
                ProfileRetryControl(deadline: model.retryAfter) {
                    Button("Повторить") { Task { await model.loadProfile() } }
                }
            }
        } else {
            ProgressView("Загружаем профиль…")
        }
    }

    private var nutritionPresentation: Binding<Bool> {
        Binding(
            get: { model.editorID != nil },
            set: { if !$0 { model.closeEditor() } }
        )
    }
}
