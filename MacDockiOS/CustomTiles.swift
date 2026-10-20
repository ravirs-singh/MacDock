import SwiftUI
import MacDockProtocol

// MARK: - Model

struct CustomTile: Codable, Identifiable, Equatable {
    enum Action: Codable, Equatable {
        case shortcut(name: String)
        case url(String)
        case app(bundleID: String, name: String)

        var command: DockCommand {
            switch self {
            case .shortcut(let name): return .runShortcut(name: name)
            case .url(let url): return .openURL(url)
            case .app(let bundleID, _): return .launchApp(bundleID: bundleID)
            }
        }
    }

    var id = UUID()
    var name: String
    var symbol: String
    var colorIndex: Int
    var action: Action

    var color: Color { TilePalette.colors[colorIndex % TilePalette.colors.count] }
}

enum TilePalette {
    static let colors: [Color] = [.red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple, .pink, .gray]
    static let symbols = [
        "bolt.fill", "star.fill", "terminal.fill", "safari.fill", "music.note", "video.fill", "camera.fill",
        "mic.fill", "doc.text.fill", "folder.fill", "envelope.fill", "message.fill", "calendar", "clock.fill",
        "lightbulb.fill", "house.fill", "wifi", "display", "keyboard", "gamecontroller.fill", "book.fill",
        "cart.fill", "hammer.fill", "wand.and.stars", "paintbrush.fill", "globe", "lock.fill", "bell.fill",
        "heart.fill", "flag.fill", "gearshape.fill", "cup.and.saucer.fill",
    ]
}

// MARK: - Store

@MainActor
final class TileStore: ObservableObject {
    @Published var tiles: [CustomTile] {
        didSet { save() }
    }

    private let key = "customTiles"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([CustomTile].self, from: data) {
            tiles = saved
        } else {
            tiles = []
        }
    }

    func upsert(_ tile: CustomTile) {
        if let i = tiles.firstIndex(where: { $0.id == tile.id }) { tiles[i] = tile } else { tiles.append(tile) }
    }

    func remove(_ tile: CustomTile) { tiles.removeAll { $0.id == tile.id } }
    func move(from: IndexSet, to: Int) { tiles.move(fromOffsets: from, toOffset: to) }

    private func save() {
        if let data = try? JSONEncoder().encode(tiles) { UserDefaults.standard.set(data, forKey: key) }
    }
}

// MARK: - Tiles section

struct CustomTilesSection: View {
    @EnvironmentObject private var client: DockClient
    @EnvironmentObject private var store: TileStore
    @State private var editing: CustomTile?
    @State private var creating = false

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("My Tiles").font(.headline)
                Spacer()
                Button { creating = true } label: {
                    Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Theme.cardHi, in: Circle())
                }
                .buttonStyle(.plain)
            }
            if store.tiles.isEmpty {
                Text("Add buttons for Shortcuts, links, or apps you use constantly.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.tiles) { tile in
                    Button { client.run(tile.action.command) } label: { TileView(tile: tile) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editing = tile }
                            Button("Delete", systemImage: "trash", role: .destructive) { store.remove(tile) }
                        }
                }
            }
        }
        .card()
        .sheet(isPresented: $creating) { TileEditor(tile: nil) }
        .sheet(item: $editing) { TileEditor(tile: $0) }
    }
}

struct TileView: View {
    let tile: CustomTile

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: tile.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(
                    LinearGradient(colors: [tile.color, tile.color.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .shadow(color: tile.color.opacity(0.4), radius: 8, y: 4)
            Text(tile.name).font(.caption2.weight(.medium)).lineLimit(1).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Editor

struct TileEditor: View {
    @EnvironmentObject private var client: DockClient
    @EnvironmentObject private var store: TileStore
    @Environment(\.dismiss) private var dismiss

    enum Kind: String, CaseIterable { case shortcut = "Shortcut", url = "Link", app = "App" }

    private let existing: CustomTile?
    @State private var name: String
    @State private var symbol: String
    @State private var colorIndex: Int
    @State private var kind: Kind
    @State private var shortcutName: String
    @State private var url: String
    @State private var app: AppInfo?
    @State private var shortcuts: [String] = []

    init(tile: CustomTile?) {
        existing = tile
        _name = State(initialValue: tile?.name ?? "")
        _symbol = State(initialValue: tile?.symbol ?? "bolt.fill")
        _colorIndex = State(initialValue: tile?.colorIndex ?? 7)
        switch tile?.action {
        case .shortcut(let n):
            _kind = State(initialValue: .shortcut); _shortcutName = State(initialValue: n); _url = State(initialValue: "")
        case .url(let u):
            _kind = State(initialValue: .url); _shortcutName = State(initialValue: ""); _url = State(initialValue: u)
        case .app(let id, let n):
            _kind = State(initialValue: .app); _shortcutName = State(initialValue: ""); _url = State(initialValue: "")
            _app = State(initialValue: AppInfo(bundleID: id, name: n, iconPNG: nil))
        case nil:
            _kind = State(initialValue: .shortcut); _shortcutName = State(initialValue: ""); _url = State(initialValue: "https://")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TileView(tile: preview).frame(width: 80)
                        TextField("Name", text: $name)
                    }
                }
                Section("Action") {
                    Picker("Type", selection: $kind) {
                        ForEach(Kind.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    switch kind {
                    case .shortcut:
                        if shortcuts.isEmpty {
                            TextField("Shortcut name", text: $shortcutName)
                        } else {
                            Picker("Shortcut", selection: $shortcutName) {
                                ForEach(shortcuts, id: \.self) { Text($0).tag($0) }
                            }
                        }
                    case .url:
                        TextField("https://…", text: $url)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    case .app:
                        Picker("App", selection: $app) {
                            Text("Choose…").tag(AppInfo?.none)
                            ForEach(client.apps) { Text($0.name).tag(AppInfo?.some($0)) }
                        }
                    }
                }
                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 10) {
                        ForEach(TilePalette.symbols, id: \.self) { s in
                            Image(systemName: s)
                                .frame(width: 44, height: 44)
                                .background(s == symbol ? Theme.accent.opacity(0.3) : Theme.cardHi,
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .onTapGesture { symbol = s }
                        }
                    }
                }
                Section("Color") {
                    HStack(spacing: 10) {
                        ForEach(TilePalette.colors.indices, id: \.self) { i in
                            Circle().fill(TilePalette.colors[i]).frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(.white, lineWidth: i == colorIndex ? 3 : 0))
                                .onTapGesture { colorIndex = i }
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Tile" : "Edit Tile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.upsert(preview); dismiss() }.disabled(!isValid)
                }
            }
            .task {
                if case .shortcuts(let list) = await client.send(.listShortcuts) {
                    shortcuts = list
                    if shortcutName.isEmpty, let first = list.first { shortcutName = first }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var action: CustomTile.Action {
        switch kind {
        case .shortcut: return .shortcut(name: shortcutName)
        case .url: return .url(url)
        case .app: return .app(bundleID: app?.bundleID ?? "", name: app?.name ?? "")
        }
    }

    private var preview: CustomTile {
        let fallback: String
        switch kind {
        case .shortcut: fallback = shortcutName
        case .url: fallback = URL(string: url)?.host ?? "Link"
        case .app: fallback = app?.name ?? "App"
        }
        return CustomTile(id: existing?.id ?? UUID(), name: name.isEmpty ? fallback : name,
                          symbol: symbol, colorIndex: colorIndex, action: action)
    }

    private var isValid: Bool {
        switch kind {
        case .shortcut: return !shortcutName.isEmpty
        case .url: return URL(string: url)?.scheme != nil && url.count > 8
        case .app: return app != nil
        }
    }
}
