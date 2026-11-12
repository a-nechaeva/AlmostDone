import SwiftUI

struct ServerMissingProducts: View {
    private enum Phase {
        case loading
        case loaded([String])
        case contextChanged
        case failed
    }

    let repository: RecommendationsRepository
    let route: RecipeRequest
    let snapshot: RecommendationPage
    let missingCount: Int
    let onRefreshSnapshot: () -> Void

    @State private var isExpanded = false
    @State private var attempt = 0
    @State private var phase = Phase.loading

    var body: some View {
        DisclosureGroup("Что докупить", isExpanded: $isExpanded) {
            switch phase {
            case .loading:
                ProgressView("Загружаем продукты…")
            case .loaded(let names):
                Text(names.joined(separator: ", "))
            case .contextChanged:
                Text("Подбор устарел")
                    .foregroundStyle(.secondary)
                Button("Обновить подбор", action: onRefreshSnapshot)
            case .failed:
                Text("Не удалось загрузить продукты")
                    .foregroundStyle(.secondary)
                Button("Повторить") { attempt += 1 }
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .task(id: isExpanded ? attempt : nil) {
            guard isExpanded else { return }
            switch phase {
            case .loaded, .contextChanged: break
            case .loading, .failed: await load()
            }
        }
    }

    private func load() async {
        phase = .loading
        do {
            let names = try await repository.missingProducts(for: route, in: snapshot, count: missingCount)
            guard canPublish else { return }
            phase = .loaded(names)
        } catch MissingProductsError.contextChanged {
            guard canPublish else { return }
            phase = .contextChanged
        } catch {
            guard canPublish else { return }
            phase = .failed
        }
    }

    private var canPublish: Bool {
        !Task.isCancelled && isExpanded && repository.session.isCurrent(repository.account)
            && (repository.session.revision?.stateVersion ?? 0) <= snapshot.stateVersion
    }
}
