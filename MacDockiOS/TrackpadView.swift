import SwiftUI
import UIKit
import MacDockProtocol

/// Full-screen trackpad: one finger moves, tap clicks, two-finger pan scrolls,
/// two-finger tap right-clicks, press-and-hold then move drags.
struct TrackpadView: View {
    @EnvironmentObject private var client: DockClient
    @State private var showKeyboard = false
    @State private var typed = ""
    @FocusState private var keyboardFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            TrackpadSurface(client: client)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.09)],
                                             startPoint: .top, endPoint: .bottom))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
                .overlay(alignment: .bottom) {
                    Text("tap · click    two-finger tap · right-click    hold · drag")
                        .font(.caption2).foregroundStyle(.white.opacity(0.3))
                        .padding(.bottom, 14)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            if showKeyboard { keyboardBar }

            HStack(spacing: 12) {
                padButton("Esc") { client.fire(.keyPress(.escape)) }
                padButton("Tab") { client.fire(.keyPress(.tab)) }
                padButton(symbol: "arrow.left") { client.fire(.keyPress(.left)) }
                padButton(symbol: "arrow.up") { client.fire(.keyPress(.up)) }
                padButton(symbol: "arrow.down") { client.fire(.keyPress(.down)) }
                padButton(symbol: "arrow.right") { client.fire(.keyPress(.right)) }
                padButton(symbol: showKeyboard ? "keyboard.chevron.compact.down" : "keyboard") {
                    showKeyboard.toggle()
                    keyboardFocused = showKeyboard
                }
            }
        }
        .padding(16)
        .background(Color.black.ignoresSafeArea())
    }

    /// Hidden-ish text field: characters are forwarded as they are typed, deletions as backspaces.
    private var keyboardBar: some View {
        HStack {
            Image(systemName: "keyboard").foregroundStyle(.secondary)
            TextField("Type on your Mac…", text: $typed)
                .focused($keyboardFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.return)
                .onChange(of: typed) { old, new in forward(old: old, new: new) }
                .onSubmit {
                    client.fire(.keyPress(.return))
                    typed = ""
                    keyboardFocused = true
                }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func forward(old: String, new: String) {
        if new.hasPrefix(old) {
            let added = String(new.dropFirst(old.count))
            if !added.isEmpty { client.fire(.typeText(added)) }
        } else if old.hasPrefix(new) {
            for _ in 0 ..< (old.count - new.count) { client.fire(.keyPress(.delete)) }
        } else {
            // Autocorrect-style replacement: delete the old tail and type the new one.
            let common = zip(old, new).prefix { $0 == $1 }.count
            for _ in 0 ..< (old.count - common) { client.fire(.keyPress(.delete)) }
            client.fire(.typeText(String(new.dropFirst(common))))
        }
        // Keep the field short so it never scrolls; the Mac has the text.
        if new.count > 40 { typed = String(new.suffix(10)) }
    }

    private func padButton(_ title: String? = nil, symbol: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let symbol { Image(systemName: symbol) } else { Text(title ?? "") }
            }
            .font(.system(size: 15, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}

/// UIKit gesture surface. SwiftUI gestures cannot distinguish finger counts reliably.
struct TrackpadSurface: UIViewRepresentable {
    let client: DockClient

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        let c = context.coordinator

        let move = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:)))
        move.maximumNumberOfTouches = 1
        let scroll = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.scroll(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        let twoTap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.rightTap(_:)))
        twoTap.numberOfTouchesRequired = 2
        let hold = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = 0.35
        hold.allowableMovement = 8

        [move, scroll, tap, twoTap, hold].forEach { view.addGestureRecognizer($0) }
        move.delegate = c
        hold.delegate = c
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(client: client) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let client: DockClient
        private var last: CGPoint = .zero
        private var dragging = false
        private var lastTap = Date.distantPast
        private let haptic = UIImpactFeedbackGenerator(style: .light)

        init(client: DockClient) { self.client = client }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            let p = g.translation(in: g.view)
            switch g.state {
            case .began: last = p
            case .changed:
                let v = g.velocity(in: g.view)
                // Mild acceleration: slow moves are precise, fast flicks cross the screen.
                let speed = hypot(v.x, v.y)
                let gain = 1.2 + min(speed / 1500, 2.0)
                let dx = (p.x - last.x) * gain, dy = (p.y - last.y) * gain
                last = p
                client.fire(dragging ? .pointerDrag(dx: dx, dy: dy) : .pointerMove(dx: dx, dy: dy))
            case .ended, .cancelled, .failed:
                if dragging { endDrag() }
            default: break
            }
        }

        @objc func scroll(_ g: UIPanGestureRecognizer) {
            let p = g.translation(in: g.view)
            switch g.state {
            case .began: last = p
            case .changed:
                client.fire(.scroll(dx: (p.x - last.x) * 2, dy: (p.y - last.y) * 2))
                last = p
            default: break
            }
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            let isDouble = Date().timeIntervalSince(lastTap) < 0.3
            lastTap = isDouble ? .distantPast : Date()
            haptic.impactOccurred()
            client.fire(.click(button: .left, count: isDouble ? 2 : 1))
        }

        @objc func rightTap(_ g: UITapGestureRecognizer) {
            haptic.impactOccurred()
            client.fire(.click(button: .right, count: 1))
        }

        @objc func hold(_ g: UILongPressGestureRecognizer) {
            switch g.state {
            case .began:
                dragging = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                client.fire(.dragBegin)
            case .ended, .cancelled, .failed:
                // The pan recognizer finishes the drag if the finger moved; otherwise end it here.
                if dragging { endDrag() }
            default: break
            }
        }

        private func endDrag() {
            dragging = false
            client.fire(.dragEnd)
        }

        // Let hold + pan run together so a drag can start from a press.
        func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
