import Foundation

nonisolated struct AccountSession: Sendable, Equatable {
    let id: UUID
    let userID: String
}

nonisolated struct AccountRevision: Codable, Sendable, Equatable {
    let stateVersion: Int
    let etag: String

    init(etag: String?, stateVersion: Int? = nil) throws {
        let prefix = "\"state-"
        guard let etag, etag.hasPrefix(prefix), etag.hasSuffix("\""),
            let version = Int(etag.dropFirst(prefix.count).dropLast()), version >= 0,
            etag == "\"state-\(version)\"", stateVersion == nil || stateVersion == version
        else { throw SessionError.invalidStateRevision }
        self.stateVersion = version
        self.etag = etag
    }
}

nonisolated struct AccountState: Decodable, Sendable {
    let userID: String
    let stateVersion: Int
    let catalogVersion: String

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case stateVersion = "state_version"
        case catalogVersion = "catalog_version"
    }
}

nonisolated enum SessionError: Error, Equatable {
    case noSession
    case sessionChanged
    case signInRequired
    case refreshRateLimited(until: Date)
    case storageUnavailable
    case invalidServerSession
    case invalidStateRevision
}

nonisolated enum LogoutResult: Equatable {
    case revoked
    case alreadyUnauthorized
    case localOnly
    case revocationUnconfirmed
}
