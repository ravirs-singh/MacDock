import SwiftUI

@main
struct MacDockHelperApp: App {
    @StateObject private var server = DockServer()

    var body: some Scene {
        // A popover window rather than a tracked menu: if the process is ever paused
        // (debugger, crash) an open menu would block input for the whole Mac.
        MenuBarExtra("MacDock", systemImage: server.isRunning ? "dock.rectangle" : "dock.rectangle.badge.xmark") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pairing PIN").font(.caption).foregroundStyle(.secondary)
                    Text(server.pin).font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                }
                Text(server.isRunning ? "Advertising as \(Host.current().localizedName ?? "Mac")" : "Stopped")
                    .font(.callout).foregroundStyle(.secondary)
                Divider()
                Text("Paired devices: \(server.pairedTokens.count)").font(.callout)
                HStack {
                    Button("Regenerate PIN") { server.regeneratePIN() }
                    Button("Forget all devices") { server.forgetAll() }
                }
                Divider()
                Button("Quit MacDock") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(16)
            .frame(width: 280)
        }
        .menuBarExtraStyle(.window)
    }
}
