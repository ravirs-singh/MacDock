import AppKit
import Carbon.HIToolbox
import MacDockProtocol

/// Drives the Mac's pointer and keyboard from iPhone touch input via CGEvent.
/// Requires Accessibility permission (System Settings → Privacy & Security → Accessibility).
@MainActor
final class InputController {
    private let source = CGEventSource(stateID: .hidSystemState)

    /// Prompts the system Accessibility dialog if the helper is not yet trusted.
    static func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func handle(_ command: DockCommand) {
        switch command {
        case .pointerMove(let dx, let dy): move(dx: dx, dy: dy, dragging: false)
        case .pointerDrag(let dx, let dy): move(dx: dx, dy: dy, dragging: true)
        case .dragBegin: mouseButton(.leftMouseDown)
        case .dragEnd: mouseButton(.leftMouseUp)
        case .click(let button, let count): click(button, count: count)
        case .scroll(let dx, let dy): scroll(dx: dx, dy: dy)
        case .typeText(let text): type(text)
        case .keyPress(let key): press(key)
        default: break
        }
    }

    // MARK: Pointer

    private var location: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func move(dx: Double, dy: Double, dragging: Bool) {
        var p = location
        p.x += dx
        p.y += dy
        // Keep the cursor inside the union of all displays (CG coordinates, origin top-left).
        let bounds = NSScreen.screens.reduce(CGRect.null) { $0.union(cgRect($1.frame)) }
        p.x = min(max(p.x, bounds.minX), bounds.maxX - 1)
        p.y = min(max(p.y, bounds.minY), bounds.maxY - 1)
        let type: CGEventType = dragging ? .leftMouseDragged : .mouseMoved
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    private func click(_ button: MouseButton, count: Int) {
        let p = location
        let (down, up, cgButton): (CGEventType, CGEventType, CGMouseButton) = button == .left
            ? (.leftMouseDown, .leftMouseUp, .left)
            : (.rightMouseDown, .rightMouseUp, .right)
        for i in 1 ... max(1, count) {
            for type in [down, up] {
                let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: cgButton)
                event?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    private func mouseButton(_ type: CGEventType) {
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    private func scroll(dx: Double, dy: Double) {
        CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    /// AppKit screen frames have a bottom-left origin; CGEvent wants top-left.
    private func cgRect(_ frame: NSRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? frame.maxY
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    // MARK: Keyboard

    private func type(_ text: String) {
        for scalar in text.unicodeScalars {
            if scalar == "\n" { press(.return); continue }
            var utf16 = Array(String(scalar).utf16)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                event?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    private func press(_ key: SpecialKey) {
        let code: Int
        switch key {
        case .return: code = kVK_Return
        case .delete: code = kVK_Delete
        case .escape: code = kVK_Escape
        case .tab: code = kVK_Tab
        case .space: code = kVK_Space
        case .up: code = kVK_UpArrow
        case .down: code = kVK_DownArrow
        case .left: code = kVK_LeftArrow
        case .right: code = kVK_RightArrow
        }
        for down in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down)?
                .post(tap: .cghidEventTap)
        }
    }
}
