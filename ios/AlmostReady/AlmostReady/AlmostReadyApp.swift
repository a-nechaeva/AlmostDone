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
            case .products:
                if let account = session.account {
                    ServerAccountRoot(session: session, account: account)
                }
            }
        }
        .id(session.account?.id)
        .environment(session)
    }
}

private struct ServerAccountRoot: View {
    @State private var favorites: FavoritesStore
    @State private var shopping: ServerShoppingModel

    init(session: SessionStore, account: AccountSession) {
        _favorites = State(initialValue: FavoritesStore(session: session, account: account))
        _shopping = State(initialValue: session.shoppingModel(for: account))
    }

    var body: some View {
        ContentView()
            .environment(favorites)
            .environment(shopping)
    }
}

private struct DemoRoot: View {
    @State private var store = DemoStore()

    var body: some View {
        ContentView()
            .environment(store)
    }
}
