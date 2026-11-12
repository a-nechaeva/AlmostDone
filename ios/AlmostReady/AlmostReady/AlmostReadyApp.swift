import SwiftUI

@main
struct AlmostReadyApp: App {
    @State private var configuration = SessionConfiguration()

    var body: some Scene {
        WindowGroup {
            switch configuration {
            case .demo:
                DemoRoot()
            case .server(let session):
                ServerRoot(session: session)
            case .invalid:
                ContentUnavailableView(
                    "Проверьте настройки подключения",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Укажите адрес API и Client ID Яндекс OAuth для серверного режима.")
                )
            }
        }
    }
}

struct ServerRoot: View {
    enum Destination: Equatable {
        case session
        case products
    }

    let session: SessionStore

    var destination: Destination {
        session.account == nil ? .session : .products
    }

    var body: some View {
        Group {
            switch destination {
            case .session: ServerSessionScreen()
            case .products: ContentView()
            }
        }
        .id(session.account?.id)
        .environment(session)
    }
}

private struct DemoRoot: View {
    @State private var store = DemoStore()

    var body: some View {
        ContentView()
            .environment(store)
    }
}
