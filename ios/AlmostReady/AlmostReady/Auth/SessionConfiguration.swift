import Foundation

enum SessionConfiguration {
    case demo
    case server(SessionStore)
    case invalid

    init(bundle: Bundle = .main) {
        let mode = bundle.object(forInfoDictionaryKey: "AlmostReadyMode") as? String
        switch mode {
        case nil, "", "demo":
            self = .demo
        case "server":
            guard let rawURL = bundle.object(forInfoDictionaryKey: "AlmostReadyAPIBaseURL") as? String,
                let baseURL = URL(string: rawURL), baseURL.scheme?.lowercased() == "https",
                let clientID = bundle.object(forInfoDictionaryKey: "AlmostReadyYandexClientID") as? String,
                !clientID.isEmpty,
                clientID.utf8.allSatisfy({
                    (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                }),
                let client = try? APIClient(baseURL: baseURL)
            else {
                self = .invalid
                return
            }
            self = .server(
                SessionStore(
                    client: client, yandex: YandexLoginProvider(clientID: clientID),
                    storage: KeychainSessionStorage(
                        service: "itmo.AlmostReady.server-session",
                        account: "\(baseURL.absoluteString)|\(clientID)"
                    )
                )
            )
        default:
            self = .invalid
        }
    }
}
