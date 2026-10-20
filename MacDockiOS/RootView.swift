import SwiftUI
import Network
import MacDockProtocol

// MARK: - Theme

enum Theme {
    static let bg = Color.black
    static let card = Color(white: 0.11)
    static let cardHi = Color(white: 0.16)
    static let accent = Color(red: 0.49, green: 0.42, blue: 1.0)
    static let radius: CGFloat = 22
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject private var client: DockClient

    var body: some View {
        Group {
            switch client.state {
            case .disconnected, .connecting:
                MacPickerView()
            case .needsPIN:
                PINEntryView()
            case .connected(let macName):
                ConnectedView(macName: macName)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .alert("Something went wrong", isPresented: Binding(
            get: { client.lastError != nil },
            set: { if !$0 { client.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(client.lastError ?? "")
        }
    }
}

struct ConnectedView: View {
    let macName: String

    var body: some View {
        TabView {
            DockView(macName: macName)
                .tabItem { Label("Dock", systemImage: "square.grid.2x2.fill") }
            TrackpadView()
                .tabItem { Label("Trackpad", systemImage: "hand.point.up.left.fill") }
        }
    }
}

// MARK: - Pick a Mac

struct MacPickerView: View {
    @EnvironmentObject private var client: DockClient

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                Image(systemName: "laptopcomputer.and.iphone")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Theme.accent)
                VStack(spacing: 6) {
                    Text("MacDock").font(.largeTitle.bold())
                    Text("Control your Mac from here").foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    if client.discovered.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Looking for your Mac…").foregroundStyle(.secondary)
                            Spacer()
                        }
                        .card()
                    }
                    ForEach(client.discovered, id: \.hashValue) { result in
                        Button { client.connect(to: result) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "laptopcomputer")
                                    .font(.title2).foregroundStyle(Theme.accent)
                                    .frame(width: 44, height: 44)
                                    .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                Text(DockClient.name(of: result) ?? "Mac").font(.headline)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .card()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                Text("Run MacDock Helper on your Mac, on the same Wi‑Fi.")
                    .font(.footnote).foregroundStyle(.tertiary)
                Spacer()
                Spacer()
            }
            if client.state == .connecting {
                ProgressView("Connecting…").padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

// MARK: - PIN

struct PINEntryView: View {
    @EnvironmentObject private var client: DockClient
    @State private var pin = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                Image(systemName: "lock.laptopcomputer")
                    .font(.system(size: 56, weight: .light)).foregroundStyle(Theme.accent)
                VStack(spacing: 6) {
                    Text("Pair with your Mac").font(.title2.bold())
                    Text("Enter the 6‑digit PIN from the MacDock icon in your Mac's menu bar.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        .padding(.horizontal, 32)
                }

                // Six boxes rendered over an invisible text field.
                ZStack {
                    TextField("", text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($focused)
                        .opacity(0.01)
                        .onChange(of: pin) { _, value in
                            pin = String(value.filter(\.isNumber).prefix(6))
                            if pin.count == 6 { Task { await client.authenticate(pin: pin) } }
                        }
                    HStack(spacing: 10) {
                        ForEach(0 ..< 6, id: \.self) { i in
                            let digit = i < pin.count ? String(pin[pin.index(pin.startIndex, offsetBy: i)]) : ""
                            Text(digit)
                                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                                .frame(width: 46, height: 58)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(i == pin.count ? Theme.accent : .white.opacity(0.08), lineWidth: 1.5))
                        }
                    }
                    .onTapGesture { focused = true }
                }
                Button("Cancel") { client.disconnect() }.foregroundStyle(.secondary)
                Spacer()
                Spacer()
            }
        }
        .onAppear { focused = true }
    }
}

// MARK: - Dock

struct DockView: View {
    @EnvironmentObject private var client: DockClient
    let macName: String
    @State private var search = ""
    @State private var pendingConfirm: DockCommand?

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 18)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    mediaCard
                    quickActions
                    CustomTilesSection()
                    appsCard
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(macName)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 6) {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text("Connected").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Refresh apps", systemImage: "arrow.clockwise") { Task { await client.refreshApps() } }
                        Button("Disconnect", systemImage: "xmark.circle", role: .destructive) { client.disconnect(forget: true) }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .searchable(text: $search, prompt: "Search apps")
            .refreshable { await client.refreshApps() }
            .confirmationDialog(
                pendingConfirm == .sleep ? "Put the Mac to sleep?" : "Lock the Mac screen?",
                isPresented: Binding(get: { pendingConfirm != nil }, set: { if !$0 { pendingConfirm = nil } }),
                titleVisibility: .visible
            ) {
                Button(pendingConfirm == .sleep ? "Sleep" : "Lock", role: .destructive) {
                    if let command = pendingConfirm { client.run(command) }
                }
            }
        }
    }

    // MARK: Media

    private var mediaCard: some View {
        VStack(spacing: 18) {
            HStack(spacing: 28) {
                mediaButton("backward.fill", size: 22) { client.run(.mediaKey(.previous)) }
                Button { client.run(.mediaKey(.playPause)) } label: {
                    Image(systemName: "playpause.fill")
                        .font(.system(size: 26, weight: .bold))
                        .frame(width: 68, height: 68)
                        .background(Theme.accent, in: Circle())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                mediaButton("forward.fill", size: 22) { client.run(.mediaKey(.next)) }
            }
            HStack(spacing: 12) {
                mediaButton("speaker.slash.fill", size: 16) { client.run(.volume(.mute)) }
                mediaButton("speaker.minus.fill", size: 16, wide: true) { client.run(.volume(.down)) }
                mediaButton("speaker.plus.fill", size: 16, wide: true) { client.run(.volume(.up)) }
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func mediaButton(_ symbol: String, size: CGFloat, wide: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(maxWidth: wide ? .infinity : nil)
                .frame(width: wide ? nil : 52, height: 48)
                .background(Theme.cardHi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: Quick actions

    private var quickActions: some View {
        HStack(spacing: 12) {
            actionTile("Lock", "lock.fill", .orange) { pendingConfirm = .lockScreen }
            actionTile("Sleep", "moon.fill", .indigo) { pendingConfirm = .sleep }
            actionTile("Finder", "folder.fill", .blue) { client.run(.launchApp(bundleID: "com.apple.finder")) }
            actionTile("Terminal", "terminal.fill", .gray) { client.run(.launchApp(bundleID: "com.apple.Terminal")) }
        }
    }

    private func actionTile(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Apps

    private var appsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Apps").font(.headline)
                Spacer()
                Text("\(filteredApps.count)").font(.caption).foregroundStyle(.secondary)
            }
            if client.apps.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 24)
            }
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(filteredApps) { app in
                    Button { client.run(.launchApp(bundleID: app.bundleID)) } label: {
                        VStack(spacing: 6) {
                            Group {
                                if let data = app.iconPNG, let image = UIImage(data: data) {
                                    Image(uiImage: image).resizable()
                                } else {
                                    Image(systemName: "app.fill").font(.system(size: 40)).foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 60, height: 60)
                            .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
                            Text(app.name).font(.caption2).lineLimit(1).foregroundStyle(.white.opacity(0.85))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card()
    }

    private var filteredApps: [AppInfo] {
        guard !search.isEmpty else { return client.apps }
        return client.apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
}
