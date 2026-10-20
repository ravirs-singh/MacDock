import Foundation

/// Bonjour service type both apps use for discovery.
public let macDockServiceType = "_macdock._tcp"

/// A command the iPhone asks the Mac to perform.
public enum DockCommand: Codable, Equatable {
    /// First message on a new connection. `pin` is the 6-digit code shown on the Mac,
    /// or the token issued after a previous successful pairing.
    case pair(pin: String?, token: String?)
    case launchApp(bundleID: String)
    case openURL(String)
    case mediaKey(MediaKey)
    case volume(VolumeAction)
    case runShortcut(name: String)
    case listShortcuts
    case lockScreen
    case sleep
    case listApps

    // Input events. These are fire-and-forget: the Mac sends no response.
    case pointerMove(dx: Double, dy: Double)
    case pointerDrag(dx: Double, dy: Double)
    case dragBegin
    case dragEnd
    case click(button: MouseButton, count: Int)
    case scroll(dx: Double, dy: Double)
    case typeText(String)
    case keyPress(SpecialKey)

    /// True for commands that expect no reply.
    public var isFireAndForget: Bool {
        switch self {
        case .pointerMove, .pointerDrag, .dragBegin, .dragEnd, .click, .scroll, .typeText, .keyPress: return true
        default: return false
        }
    }
}

public enum MouseButton: String, Codable { case left, right }

public enum SpecialKey: String, Codable {
    case `return`, delete, escape, tab, space, up, down, left, right
}

public enum MediaKey: String, Codable {
    case playPause, next, previous, mute
}

public enum VolumeAction: Codable, Equatable {
    case up, down, mute
    case set(Int) // 0–100
}

/// Response from the Mac.
public enum DockResponse: Codable, Equatable {
    case ok
    case paired(token: String, macName: String)
    case unauthorized
    case apps([AppInfo])
    case shortcuts([String])
    case error(String)
}

public struct AppInfo: Codable, Equatable, Identifiable, Hashable {
    public var id: String { bundleID }
    public let bundleID: String
    public let name: String
    /// PNG-encoded icon, downscaled. Optional to keep the app list small.
    public let iconPNG: Data?

    public init(bundleID: String, name: String, iconPNG: Data?) {
        self.bundleID = bundleID
        self.name = name
        self.iconPNG = iconPNG
    }
}

/// Length-prefixed JSON framing: 4-byte big-endian length followed by the JSON body.
public enum Framing {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let body = try JSONEncoder().encode(value)
        var length = UInt32(body.count).bigEndian
        var data = Data(bytes: &length, count: 4)
        data.append(body)
        return data
    }

    /// Returns the decoded value and the number of bytes consumed, or nil if the buffer
    /// does not yet hold a complete frame.
    public static func decode<T: Decodable>(_ type: T.Type, from buffer: Data) throws -> (T, Int)? {
        // `Data` slices keep their original indices (startIndex is not 0 after
        // removeFirst), so every range must be relative to startIndex.
        guard buffer.count >= 4 else { return nil }
        let start = buffer.startIndex
        let length = Int(UInt32(bigEndian: buffer[start ..< start + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
        guard buffer.count >= 4 + length else { return nil }
        let body = buffer[start + 4 ..< start + 4 + length]
        return (try JSONDecoder().decode(type, from: body), 4 + length)
    }
}
