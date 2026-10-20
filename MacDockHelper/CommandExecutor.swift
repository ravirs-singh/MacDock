import AppKit
import MacDockProtocol

/// Performs commands on the Mac. Everything here runs on the main actor because
/// NSWorkspace and the media-key event posting expect it.
@MainActor
final class CommandExecutor {
    func execute(_ command: DockCommand) async -> DockResponse {
        switch command {
        case .pair:
            return .error("pair handled by server")
        case .launchApp(let bundleID):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                return .error("App not found: \(bundleID)")
            }
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
            return .ok
        case .openURL(let string):
            guard let url = URL(string: string) else { return .error("Bad URL") }
            NSWorkspace.shared.open(url)
            return .ok
        case .mediaKey(let key):
            MediaKeys.press(key)
            return .ok
        case .volume(let action):
            return runAppleScript(volumeScript(for: action))
        case .runShortcut(let name):
            return runProcess("/usr/bin/shortcuts", ["run", name])
        case .lockScreen:
            // Same as ⌃⌘Q.
            return runProcess("/usr/bin/osascript", ["-e",
                "tell application \"System Events\" to keystroke \"q\" using {command down, control down}"])
        case .sleep:
            return runProcess("/usr/bin/pmset", ["sleepnow"])
        case .listApps:
            return .apps(installedApps())
        }
    }

    // MARK: - Helpers

    private func volumeScript(for action: VolumeAction) -> String {
        switch action {
        case .up: return "set volume output volume ((output volume of (get volume settings)) + 10)"
        case .down: return "set volume output volume ((output volume of (get volume settings)) - 10)"
        case .mute: return "set volume with output muted"
        case .set(let level): return "set volume output volume \(max(0, min(100, level)))"
        }
    }

    private func runAppleScript(_ source: String) -> DockResponse {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { return .error("\(error)") }
        return .ok
    }

    private func runProcess(_ path: String, _ args: [String]) -> DockResponse {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        do {
            try process.run()
            return .ok
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private func installedApps() -> [AppInfo] {
        let dirs = ["/Applications", "/System/Applications", "\(NSHomeDirectory())/Applications"]
        var result: [AppInfo] = []
        for dir in dirs {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for name in names where name.hasSuffix(".app") {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
                let display = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? String(name.dropLast(4))
                result.append(AppInfo(bundleID: id, name: display, iconPNG: iconPNG(for: url)))
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func iconPNG(for appURL: URL, size: CGFloat = 64) -> Data? {
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        let small = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            icon.draw(in: rect)
            return true
        }
        guard let tiff = small.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// Posts the special media-key events the keyboard's F7–F10 send.
enum MediaKeys {
    private static let NX_KEYTYPE_PLAY: Int32 = 16
    private static let NX_KEYTYPE_NEXT: Int32 = 17
    private static let NX_KEYTYPE_PREVIOUS: Int32 = 18
    private static let NX_KEYTYPE_MUTE: Int32 = 7

    static func press(_ key: MediaKey) {
        let code: Int32
        switch key {
        case .playPause: code = NX_KEYTYPE_PLAY
        case .next: code = NX_KEYTYPE_NEXT
        case .previous: code = NX_KEYTYPE_PREVIOUS
        case .mute: code = NX_KEYTYPE_MUTE
        }
        post(code, down: true)
        post(code, down: false)
    }

    private static func post(_ code: Int32, down: Bool) {
        let flags: NSEvent.ModifierFlags = down ? .init(rawValue: 0xA00) : .init(rawValue: 0xB00)
        let data1 = Int((code << 16) | ((down ? 0xA : 0xB) << 8))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1
        ) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
