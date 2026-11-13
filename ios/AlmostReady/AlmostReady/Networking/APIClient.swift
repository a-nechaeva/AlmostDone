import Foundation

nonisolated struct HTTPResponseMetadata: Sendable, Equatable {
    let statusCode: Int
    let etag: String?
    let retryAfter: String?
    let contentType: String?

    init(_ response: HTTPURLResponse) {
        statusCode = response.statusCode
        etag = response.value(forHTTPHeaderField: "ETag")
        retryAfter = response.value(forHTTPHeaderField: "Retry-After")
        contentType = response.value(forHTTPHeaderField: "Content-Type")
    }
}

nonisolated struct APIResponse<Value: Sendable>: Sendable {
    let value: Value
    let metadata: HTTPResponseMetadata
}

nonisolated struct APIErrorPayload: Decodable, Sendable, Equatable {
    nonisolated struct Detail: Decodable, Sendable, Equatable {
        let field: String
        let code: String
        let message: String
    }

    let code: String
    let message: String
    let retryable: Bool
    let requestID: String
    let details: [Detail]

    private enum CodingKeys: String, CodingKey {
        case code, message, retryable, details
        case requestID = "request_id"
    }
}

nonisolated enum APIClientError: Error {
    case invalidConfiguration
    case invalidRequest
    case encodingFailed
    case network(URLError.Code?)
    case cancelled
    case invalidResponse(HTTPResponseMetadata?)
    case server(APIErrorPayload, HTTPResponseMetadata)

    var metadata: HTTPResponseMetadata? {
        switch self {
        case .invalidResponse(let metadata):
            metadata
        case .server(_, let metadata):
            metadata
        default:
            nil
        }
    }
}

/// Pass the current bearer token with each protected request. DTOs use the contract's JSON keys.
///
/// ```swift
/// let state = try await client.json(
///     StateDTO.self,
///     for: APIRequest(path: ["me", "state"], headers: .init(bearerToken: accessToken))
/// )
/// let photo = try await client.data(for: APIRequest(path: ["recipes", recipeID, "photo"]))
/// ```
nonisolated struct APIClient: Sendable {
    private struct ErrorEnvelope: Decodable {
        let error: APIErrorPayload
    }

    private static let apiPrefix = ["api", "v1"]
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    let serverIdentity: String
    private let base: URLComponents
    private let timeout: TimeInterval
    private let transport: any HTTPTransport

    init(
        baseURL: URL,
        timeout: TimeInterval = 30,
        transport: any HTTPTransport = URLSessionTransport()
    ) throws {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true),
            let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = components.host, !host.isEmpty,
            components.user == nil, components.password == nil,
            components.query == nil, components.fragment == nil,
            timeout.isFinite, timeout > 0
        else {
            throw APIClientError.invalidConfiguration
        }

        while components.percentEncodedPath.hasSuffix("/") {
            components.percentEncodedPath.removeLast()
        }
        let segments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        let decoded = segments.map { $0.removingPercentEncoding ?? String($0) }
        if let prefixStart = decoded.indices.first(where: { decoded[$0...].starts(with: Self.apiPrefix) }) {
            guard prefixStart == decoded.count - Self.apiPrefix.count else {
                throw APIClientError.invalidConfiguration
            }
            components.percentEncodedPath = segments.prefix(prefixStart).joined(separator: "/")
        }
        components.percentEncodedPath += "/" + Self.apiPrefix.joined(separator: "/")

        base = components
        components.scheme = scheme
        components.host = host.lowercased()
        if (scheme == "https" && components.port == 443) || (scheme == "http" && components.port == 80) {
            components.port = nil
        }
        guard let serverIdentity = components.string else { throw APIClientError.invalidConfiguration }
        self.serverIdentity = serverIdentity
        self.timeout = timeout
        self.transport = transport
    }

    func json<Value: Decodable & Sendable>(
        _ type: Value.Type,
        for request: APIRequest
    ) async throws -> APIResponse<Value> {
        let response = try await send(request, accept: "application/json")
        do {
            let value = try JSONDecoder().decode(type, from: response.value)
            return APIResponse(value: value, metadata: response.metadata)
        } catch {
            throw APIClientError.invalidResponse(response.metadata)
        }
    }

    func empty(for request: APIRequest) async throws -> APIResponse<Void> {
        let response = try await send(request, accept: "application/json")
        guard response.value.isEmpty else {
            throw APIClientError.invalidResponse(response.metadata)
        }
        return APIResponse(value: (), metadata: response.metadata)
    }

    func data(for request: APIRequest) async throws -> APIResponse<Data> {
        try await send(request, accept: "*/*")
    }

    private func send(_ request: APIRequest, accept: String) async throws -> APIResponse<Data> {
        guard !Task.isCancelled else { throw APIClientError.cancelled }
        let urlRequest = try makeURLRequest(request, accept: accept)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: urlRequest)
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw APIClientError.cancelled
            }
            throw APIClientError.network((error as? URLError)?.code)
        }

        guard !Task.isCancelled else { throw APIClientError.cancelled }
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse(nil)
        }

        let metadata = HTTPResponseMetadata(http)
        guard (200..<300).contains(metadata.statusCode) else {
            guard let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) else {
                throw APIClientError.invalidResponse(metadata)
            }
            throw APIClientError.server(envelope.error, metadata)
        }
        return APIResponse(value: data, metadata: metadata)
    }

    private func makeURLRequest(_ request: APIRequest, accept: String) throws -> URLRequest {
        var components = base
        guard !request.path.isEmpty, !request.path.starts(with: Self.apiPrefix) else {
            throw APIClientError.invalidRequest
        }
        for segment in request.path {
            guard !segment.isEmpty else { throw APIClientError.invalidRequest }
            let encoded =
                switch segment {
                case ".": "%2E"
                case "..": "%2E%2E"
                default: try Self.encode(segment)
                }
            components.percentEncodedPath += "/" + encoded
        }
        if !request.query.isEmpty {
            // URLComponents leaves '+' in query items, where form-style parsers read it as a space.
            components.percentEncodedQueryItems = try request.query.map { item in
                URLQueryItem(name: try Self.encode(item.name), value: try item.value.map(Self.encode))
            }
        }
        guard let url = components.url else { throw APIClientError.invalidRequest }

        var result = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        result.httpMethod = request.method.rawValue
        result.httpShouldHandleCookies = false
        result.setValue(accept, forHTTPHeaderField: "Accept")
        result.setValue(request.headers.bearerToken.map { "Bearer \($0)" }, forHTTPHeaderField: "Authorization")
        result.setValue(request.headers.ifMatch, forHTTPHeaderField: "If-Match")
        result.setValue(request.headers.idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        if let multipart = request.multipartBody {
            guard request.jsonBody == nil else { throw APIClientError.invalidRequest }
            let boundary = "AlmostReady-\(UUID().uuidString)"
            result.httpBody = try Self.encode(multipart, boundary: boundary)
            result.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        } else if let body = request.jsonBody {
            do {
                result.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw APIClientError.encodingFailed
            }
            result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return result
    }

    private static func encode(_ body: APIRequest.MultipartBody, boundary: String) throws -> Data {
        let file = body.file
        let mediaTypeCharacters = unreserved.union(CharacterSet(charactersIn: "/"))
        guard
            ([file.field, file.name] + body.fields.keys).allSatisfy({
                !$0.isEmpty && $0.unicodeScalars.allSatisfy(unreserved.contains)
            }), !file.contentType.isEmpty, file.contentType.unicodeScalars.allSatisfy(mediaTypeCharacters.contains)
        else { throw APIClientError.invalidRequest }

        var data = Data()
        for (name, value) in body.fields.sorted(by: { $0.key < $1.key }) {
            data.append(
                contentsOf: "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8
            )
        }
        data.append(
            contentsOf:
                "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(file.field)\"; filename=\"\(file.name)\"\r\n"
                .utf8)
        data.append(contentsOf: "Content-Type: \(file.contentType)\r\n\r\n".utf8)
        data.append(file.data)
        data.append(contentsOf: "\r\n--\(boundary)--\r\n".utf8)
        return data
    }

    private static func encode(_ value: String) throws -> String {
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: unreserved) else {
            throw APIClientError.invalidRequest
        }
        return encoded
    }
}
