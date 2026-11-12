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
                ServerSessionScreen()
                    .id(session.account?.id)
                    .environment(session)
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

private struct DemoRoot: View {
    @State private var store = DemoStore()

    var body: some View {
        ContentView()
            .environment(store)
    }
}
