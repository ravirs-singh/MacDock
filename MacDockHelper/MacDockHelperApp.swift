import SwiftUI
import ServiceManagement

@main
struct MacDockHelperApp: App {
    @StateObject private var server = DockServer()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    init() {
        // Defer until the run loop is up so the alert can be shown.
        DispatchQueue.main.async {
            SelfInstaller.promptIfNeeded()
            InputController.requestAccessibilityIfNeeded()
        }
    }

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
                if !SelfInstaller.isInstalled {
                    Button("Install to Applications…") { SelfInstaller.install() }
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                Divider()
                Button("Quit MacDock") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(16)
            .frame(width: 280)
        }
        .menuBarExtraStyle(.window)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Launch at login change failed: \(error)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
