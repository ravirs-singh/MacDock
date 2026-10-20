import SwiftUI

@main
struct MacDockHelperApp: App {
    @StateObject private var server = DockServer()

    var body: some Scene {
        MenuBarExtra("MacDock", systemImage: server.isRunning ? "dock.rectangle" : "dock.rectangle.badge.xmark") {
            Text("Pairing PIN: \(server.pin)")
                .font(.system(.title2, design: .monospaced))
            Text(server.isRunning ? "Advertising as \(Host.current().localizedName ?? "Mac")" : "Stopped")
                .foregroundStyle(.secondary)
            Divider()
            Text("Paired devices: \(server.pairedTokens.count)")
            Button("Forget all devices") { server.forgetAll() }
            Button("Regenerate PIN") { server.regeneratePIN() }
            Divider()
            Button("Quit MacDock") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}
