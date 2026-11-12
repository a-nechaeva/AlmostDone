import Foundation

nonisolated struct SessionTokens: Codable, Sendable, Equatable {
    let userID: String
    let accessToken: String
    let refreshToken: String
    var refreshNotBefore: Date? = nil
}

nonisolated enum StoredSession: Codable, Sendable, Equatable {
    case active(SessionTokens)
    case refreshing
}

@MainActor
protocol SessionStorage {
    func load() throws -> StoredSession?
    func save(_ session: StoredSession) throws
    func remove() throws
}

@MainActor
protocol YandexAuthorizing {
    func oauthToken() async throws -> String
}

nonisolated enum YandexAuthorizationError: Error {
    case cancelled
    case unavailable
}

nonisolated struct ServerSessionResponse: Decodable, Sendable {
    let userID: String
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshExpiresIn: Int

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshExpiresIn = "refresh_expires_in"
    }

    func tokens() throws -> SessionTokens {
        guard !userID.isEmpty, userID.count <= 128, !accessToken.isEmpty, !refreshToken.isEmpty,
            tokenType == "Bearer", expiresIn > 0, refreshExpiresIn > 0
        else { throw SessionError.invalidServerSession }
        return SessionTokens(userID: userID, accessToken: accessToken, refreshToken: refreshToken)
    }
}

nonisolated struct YandexExchange: Encodable, Sendable {
    let oauthToken: String

    private enum CodingKeys: String, CodingKey {
        case oauthToken = "oauth_token"
    }
}

nonisolated struct SessionRefresh: Encodable, Sendable {
    let refreshToken: String

    private enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}
