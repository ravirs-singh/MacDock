import SwiftUI

@main
struct MacDockApp: App {
    @StateObject private var client = DockClient()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(client)
        }
    }
}
