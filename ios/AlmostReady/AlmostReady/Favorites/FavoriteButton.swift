import SwiftUI

struct FavoriteButton: View {
    @Environment(FavoritesStore.self) private var favorites: FavoritesStore?
    let category: FavoritesCategory
    let entry: FavoriteEntry

    var body: some View {
        if let favorites {
            let state = favorites.state(for: category)
            if let deadline = state.retryAfter, !state.canRequest() {
                TimelineView(.explicit([.now, deadline])) { context in
                    button(favorites, state: state)
                        .disabled(!state.canRequest(at: context.date))
                }
            } else {
                button(favorites, state: state)
            }
        }
    }

    private func button(_ favorites: FavoritesStore, state: FavoritesStore.State) -> some View {
        let membership = state.membership(of: entry.id)
        let failed = state.failedChanges[entry.id]
        let reload = state.loadFailed && failed == nil
        let change = state.change(for: entry)

        return Button {
            Task {
                if reload {
                    await favorites.load(category, force: true)
                } else if let change {
                    await favorites.set(change, in: category)
                }
            }
        } label: {
            Group {
                if let membership {
                    Image(systemName: membership ? "heart.fill" : "heart")
                        .overlay(alignment: .bottomTrailing) {
                            if failed != nil || reload {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.caption2)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .orange)
                                    .offset(x: 5, y: 4)
                            }
                        }
                } else if reload {
                    Image(systemName: "arrow.clockwise")
                } else {
                    ProgressView()
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(actionLabel(isFavorite: membership, failed: failed, reload: reload))
        .accessibilityValue(membership.map { $0 ? "В избранном" : "Не в избранном" } ?? "")
        .accessibilityIdentifier("favorites.toggle.\(category.rawValue).\(entry.id)")
        .disabled(state.isLoading || state.isSaving || (!reload && change == nil))
    }

    private func actionLabel(isFavorite: Bool?, failed: FavoritesStore.Change?, reload: Bool) -> String {
        if let failed {
            let action = failed.isFavorite ? "добавить в избранное" : "удалить из избранного"
            return "Не удалось \(action): \(entry.name). Повторить"
        }
        if reload { return "Повторить загрузку избранного" }
        switch isFavorite {
        case true?: return "Удалить из избранного: \(entry.name)"
        case false?: return "Добавить в избранное: \(entry.name)"
        case nil: return "Загружаем избранное"
        }
    }
}
