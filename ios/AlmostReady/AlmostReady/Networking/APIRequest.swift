import Foundation

nonisolated enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

nonisolated struct APIRequest: Sendable {
    nonisolated struct Headers: Sendable {
        var bearerToken: String? = nil
        var ifMatch: String? = nil
        /// Operation UUID. Keep the same key for any caller-initiated retry.
        var idempotencyKey: String? = nil
    }

    nonisolated struct MultipartBody: Sendable {
        let fields: [String: String]
        let file: File

        nonisolated struct File: Sendable {
            let field: String
            let name: String
            let contentType: String
            let data: Data
        }
    }

    /// Raw path segments relative to /api/v1. Pass each ID as a single, unescaped segment.
    let path: [String]
    var method: HTTPMethod = .get
    var query: [URLQueryItem] = []
    var headers = Headers()
    var jsonBody: (any Encodable & Sendable)? = nil
    var multipartBody: MultipartBody? = nil
}
