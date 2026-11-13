#if DEBUG && targetEnvironment(simulator)
    import Foundation

    enum DishesGraphTestSession {
        static func make() -> SessionStore? {
            guard let fixture = ProcessInfo.processInfo.environment["ALMOSTREADY_GRAPH_TEST_RESPONSES"],
                let responses = try? JSONDecoder().decode([String: Response].self, from: Data(fixture.utf8)),
                let url = URL(string: "https://graph-ui-test.invalid/\(UUID())"),
                let client = try? APIClient(baseURL: url, transport: Transport(responses: responses))
            else { return nil }
            return SessionStore(client: client, yandex: Login(), storage: Storage())
        }

        nonisolated struct Response: Decodable, Sendable {
            let status: Int
            let body: String
            var once: Bool?
        }

        private actor Transport: HTTPTransport {
            private var responses: [String: Response]
            private var requestIDs: [String: String] = [:]

            init(responses: [String: Response]) {
                self.responses = responses
            }

            func data(for request: URLRequest) async throws -> (Data, URLResponse) {
                guard let url = request.url, let prefix = url.path.range(of: "/api/v1/"),
                    request.value(forHTTPHeaderField: "Authorization") == "Bearer mock-access"
                else { throw URLError(.badURL) }

                let path = String(url.path[prefix.lowerBound...])
                let key = "\(request.httpMethod ?? "") \(path)"
                guard let fixture = responses[key],
                    let response = HTTPURLResponse(
                        url: url, statusCode: fixture.status, httpVersion: nil, headerFields: ["ETag": #""state-7""#])
                else { throw URLError(.resourceUnavailable) }
                if fixture.once == true { responses[key] = nil }

                var body = fixture.body
                if key == "POST /api/v1/recommendations",
                    let data = request.httpBody,
                    let creation = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let requestID = creation["request_id"] as? String,
                    let page = try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
                    let snapshotID = page["snapshot_id"] as? String
                {
                    requestIDs[snapshotID] = requestID
                    body = body.replacingOccurrences(of: "$request_id", with: requestID)
                } else if path.hasSuffix("/graph"),
                    let snapshotID = path.split(separator: "/").dropLast().last,
                    let requestID = requestIDs[String(snapshotID)]
                {
                    body = body.replacingOccurrences(of: "$request_id", with: requestID)
                }
                return (Data(body.utf8), response)
            }
        }

        private struct Login: YandexAuthorizing {
            func oauthToken() async throws -> String { throw YandexAuthorizationError.unavailable }
        }

        private final class Storage: SessionStorage {
            private var session: StoredSession? = .active(
                SessionTokens(userID: "graph-test", accessToken: "mock-access", refreshToken: "mock-refresh"))
            func load() throws -> StoredSession? { session }
            func save(_ session: StoredSession) throws { self.session = session }
            func remove() throws { session = nil }

            nonisolated deinit {}
        }
    }
#endif
