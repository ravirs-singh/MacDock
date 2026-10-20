import AppKit

/// Copies the running bundle into /Applications and relaunches from there, so the
/// helper is a permanent app rather than a build product living in DerivedData.
@MainActor
enum SelfInstaller {
    static let destination = URL(fileURLWithPath: "/Applications/MacDockHelper.app")
    private static let suppressKey = "suppressInstallPrompt"

    static var isInstalled: Bool {
        Bundle.main.bundleURL.standardizedFileURL == destination.standardizedFileURL
    }

    /// Ask once per launch unless the user chose "don't ask again".
    static func promptIfNeeded() {
        guard !isInstalled, !UserDefaults.standard.bool(forKey: suppressKey) else { return }

        let alert = NSAlert()
        alert.messageText = "Install MacDock to Applications?"
        alert.informativeText = "MacDock will copy itself to /Applications and relaunch from there, so it keeps working after Xcode closes."
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: suppressKey)
        }
        if response == .alertFirstButtonReturn { install() }
    }

    static func install() {
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: Bundle.main.bundleURL, to: destination)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Could not install to Applications"
            alert.runModal()
            return
        }

        // Launch the installed copy, then quit this one.
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: config) { _, error in
            Task { @MainActor in
                if let error {
                    NSAlert(error: error).runModal()
                } else {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
}
