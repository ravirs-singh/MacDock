import SwiftUI
import Network
import MacDockProtocol

struct RootView: View {
    @EnvironmentObject private var client: DockClient

    var body: some View {
        NavigationStack {
            Group {
                switch client.state {
                case .disconnected, .connecting:
                    MacPickerView()
                case .needsPIN:
                    PINEntryView()
                case .connected(let macName):
                    DockView(macName: macName)
                }
            }
            .navigationTitle("MacDock")
            .alert("Error", isPresented: Binding(
                get: { client.lastError != nil },
                set: { if !$0 { client.lastError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(client.lastError ?? "")
            }
        }
    }
}

// MARK: - Pick a Mac

struct MacPickerView: View {
    @EnvironmentObject private var client: DockClient

    var body: some View {
        List {
            Section("Macs on this network") {
                if client.discovered.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Looking for MacDock Helper…").foregroundStyle(.secondary)
                    }
                }
                ForEach(client.discovered, id: \.hashValue) { result in
                    Button {
                        client.connect(to: result)
                    } label: {
                        Label(name(of: result), systemImage: "laptopcomputer")
                    }
                }
            }
            Section {
                Text("Run MacDock Helper on your Mac and make sure both devices are on the same Wi‑Fi.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .overlay {
            if client.state == .connecting { ProgressView("Connecting…") }
        }
    }

    private func name(of result: NWBrowser.Result) -> String {
        DockClient.name(of: result) ?? "Mac"
    }
}

// MARK: - PIN

struct PINEntryView: View {
    @EnvironmentObject private var client: DockClient
    @State private var pin = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.laptopcomputer").font(.system(size: 56))
            Text("Enter the 6‑digit PIN shown in the MacDock menu bar icon on your Mac.")
                .multilineTextAlignment(.center)
            TextField("PIN", text: $pin)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(.largeTitle, design: .monospaced))
                .multilineTextAlignment(.center)
                .focused($focused)
                .onChange(of: pin) { _, value in
                    pin = String(value.filter(\.isNumber).prefix(6))
                    if pin.count == 6 { Task { await client.authenticate(pin: pin) } }
                }
            Button("Cancel") { client.disconnect() }
        }
        .padding()
        .onAppear { focused = true }
    }
}

// MARK: - The dock

struct DockView: View {
    @EnvironmentObject private var client: DockClient
    let macName: String
    @State private var search = ""
    @State private var pendingConfirm: DockCommand?

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                controlsSection
                appsSection
            }
            .padding()
        }
        .navigationTitle(macName)
        .searchable(text: $search, prompt: "Search apps")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Refresh apps") { Task { await client.refreshApps() } }
                    Button("Disconnect", role: .destructive) { client.disconnect(forget: true) }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
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

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Controls").font(.headline)
            LazyVGrid(columns: columns, spacing: 16) {
                tile("Prev", "backward.fill") { client.run(.mediaKey(.previous)) }
                tile("Play", "playpause.fill") { client.run(.mediaKey(.playPause)) }
                tile("Next", "forward.fill") { client.run(.mediaKey(.next)) }
                tile("Vol −", "speaker.minus.fill") { client.run(.volume(.down)) }
                tile("Vol +", "speaker.plus.fill") { client.run(.volume(.up)) }
                tile("Mute", "speaker.slash.fill") { client.run(.volume(.mute)) }
                tile("Lock", "lock.fill") { pendingConfirm = .lockScreen }
                tile("Sleep", "moon.zzz.fill") { pendingConfirm = .sleep }
            }
        }
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apps").font(.headline)
            if client.apps.isEmpty {
                ProgressView("Loading apps…")
            }
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filteredApps) { app in
                    Button { client.run(.launchApp(bundleID: app.bundleID)) } label: {
                        VStack {
                            if let data = app.iconPNG, let image = UIImage(data: data) {
                                Image(uiImage: image).resizable().frame(width: 56, height: 56)
                            } else {
                                Image(systemName: "app.fill").font(.system(size: 44))
                            }
                            Text(app.name).font(.caption).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var filteredApps: [AppInfo] {
        guard !search.isEmpty else { return client.apps }
        return client.apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private func tile(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.title2)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
