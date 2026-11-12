import Foundation

enum FavoritesCategory: String {
    case recipes
    case ingredients
}

struct FavoriteEntry: Identifiable, Equatable {
    let id: String
    let name: String
    var allowedUnits: [PantryUnit] = []
}

struct FavoritesSnapshot {
    let revision: AccountRevision
    var entries: [FavoriteEntry]
}

private nonisolated struct FavoriteRecipe: Decodable, Sendable {
    let id: String
    let title: String
}

private nonisolated struct FavoriteIngredient: Decodable, Sendable {
    let id: String
    let name: String
    let allowedUnits: [PantryUnit]

    private enum CodingKeys: String, CodingKey {
        case id, name
        case allowedUnits = "allowed_units"
    }
}

private nonisolated struct FavoritesPage<Item: Decodable & Sendable>: Decodable, Sendable {
    nonisolated struct Page: Decodable, Sendable {
        let nextCursor: String?
        let hasMore: Bool

        private enum CodingKeys: String, CodingKey {
            case nextCursor = "next_cursor"
            case hasMore = "has_more"
        }
    }

    let stateVersion: Int
    let catalogVersion: String?
    let items: [Item]
    let page: Page

    private enum CodingKeys: String, CodingKey {
        case stateVersion = "state_version"
        case catalogVersion = "catalog_version"
        case items, page
    }
}

private nonisolated struct FavoriteMutation: Decodable, Sendable {
    let stateVersion: Int

    private enum CodingKeys: String, CodingKey {
        case stateVersion = "state_version"
    }
}

private enum FavoritesRepositoryError: Error {
    case changedPage
    case invalidPage
}

struct FavoritesRepository {
    let session: SessionStore
    let account: AccountSession

    var isCurrent: Bool { session.isCurrent(account) }

    func list(_ category: FavoritesCategory) async throws -> FavoritesSnapshot {
        do {
            return try await read(category)
        } catch FavoritesRepositoryError.changedPage {
            return try await read(category)
        } catch APIClientError.server(let error, _) where error.code == "context_changed" {
            return try await read(category)
        }
    }

    func reconcile(_ category: FavoritesCategory) async throws -> FavoritesSnapshot {
        try await session.reloadRevision(for: account)
        return try await list(category)
    }

    func set(
        _ isFavorite: Bool, id: String, category: FavoritesCategory, revision: AccountRevision
    ) async throws -> AccountRevision {
        let response = try await session.json(
            FavoriteMutation.self,
            for: APIRequest(
                path: path(category) + [id], method: isFavorite ? .put : .delete,
                headers: .init(ifMatch: revision.etag)
            ),
            account: account
        )
        let updated = try AccountRevision(etag: response.metadata.etag, stateVersion: response.value.stateVersion)
        guard updated.stateVersion >= revision.stateVersion else { throw SessionError.invalidStateRevision }
        try session.confirmMutation(response.metadata, stateVersion: updated.stateVersion, account: account)
        return updated
    }

    private func read(_ category: FavoritesCategory) async throws -> FavoritesSnapshot {
        switch category {
        case .recipes:
            try await pages(FavoriteRecipe.self, category: category) { FavoriteEntry(id: $0.id, name: $0.title) }
        case .ingredients:
            try await pages(FavoriteIngredient.self, category: category) {
                FavoriteEntry(id: $0.id, name: $0.name, allowedUnits: $0.allowedUnits)
            }
        }
    }

    private func pages<Item: Decodable & Sendable>(
        _ type: Item.Type, category: FavoritesCategory, entry: (Item) -> FavoriteEntry
    ) async throws -> FavoritesSnapshot {
        var snapshot: FavoritesSnapshot?
        var catalogVersion: String?
        var cursor: String?
        var seenCursors: Set<String> = []
        repeat {
            let query = cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? []
            let response = try await session.json(
                FavoritesPage<Item>.self,
                for: APIRequest(path: path(category), query: query),
                account: account
            )
            let page = response.value
            if category == .ingredients, page.catalogVersion?.isEmpty != false {
                throw FavoritesRepositoryError.invalidPage
            }
            let revision = try AccountRevision(etag: response.metadata.etag, stateVersion: page.stateVersion)
            if let existing = snapshot {
                guard existing.revision == revision, catalogVersion == page.catalogVersion else {
                    throw FavoritesRepositoryError.changedPage
                }
            } else {
                snapshot = FavoritesSnapshot(revision: revision, entries: [])
                catalogVersion = page.catalogVersion
            }
            snapshot?.entries.append(contentsOf: page.items.map(entry))
            cursor = page.page.nextCursor
            guard page.page.hasMore == (cursor != nil) else { throw FavoritesRepositoryError.invalidPage }
            if let cursor, !seenCursors.insert(cursor).inserted {
                throw FavoritesRepositoryError.invalidPage
            }
        } while cursor != nil
        guard let snapshot else { throw FavoritesRepositoryError.invalidPage }
        return snapshot
    }

    private func path(_ category: FavoritesCategory) -> [String] {
        ["me", "favorites", category.rawValue]
    }
}
