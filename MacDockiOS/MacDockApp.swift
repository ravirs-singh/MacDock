import SwiftUI

@main
struct MacDockApp: App {
    @StateObject private var client = DockClient()
    @StateObject private var tiles = TileStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(client)
                .environmentObject(tiles)
        }
        .onChange(of: scenePhase) { _, phase in
            // iOS drops idle sockets in the background; pick the connection back up.
            if phase == .active { client.autoConnectIfPossible() }
        }
    }
}
