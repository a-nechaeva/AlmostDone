import SwiftUI

@main
struct AlmostReadyApp: App {
    @State private var store = DemoStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
