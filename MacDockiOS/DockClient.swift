import Foundation
import Network
import MacDockProtocol

/// Discovers Macs via Bonjour and talks to the selected one.
@MainActor
final class DockClient: ObservableObject {
    enum State: Equatable {
        case disconnected, connecting, needsPIN, connected(macName: String)
    }

    @Published private(set) var discovered: [NWBrowser.Result] = []
    @Published private(set) var state: State = .disconnected
    @Published private(set) var apps: [AppInfo] = []
    @Published var lastError: String?

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var buffer = Data()
    private var pending: [CheckedContinuation<DockResponse, Never>] = []
    private var currentEndpoint: NWEndpoint?

    init() { startBrowsing() }

    // MARK: Discovery

    func startBrowsing() {
        let browser = NWBrowser(for: .bonjour(type: macDockServiceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self else { return }
                self.discovered = Array(results)
                self.autoConnectIfPossible()
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    // MARK: Connection

    func connect(to result: NWBrowser.Result) {
        disconnect()
        state = .connecting
        currentEndpoint = result.endpoint
        let connection = NWConnection(to: result.endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] nwState in
            Task { @MainActor in
                guard let self else { return }
                switch nwState {
                case .ready:
                    self.receive()
                    await self.authenticate(pin: nil)
                case .failed(let error):
                    self.lastError = error.localizedDescription
                    self.state = .disconnected
                    self.autoConnectIfPossible()
                case .cancelled:
                    self.state = .disconnected
                default: break
                }
            }
        }
        connection.start(queue: .main)
        self.connection = connection
    }

    /// User explicitly left; do not auto-reconnect until they pick a Mac again.
    func disconnect(forget: Bool = false) {
        connection?.cancel()
        connection = nil
        buffer = Data()
        state = .disconnected
        if forget { lastMacName = nil }
    }

    /// Connect to the last-used Mac as soon as Bonjour sees it.
    func autoConnectIfPossible() {
        guard state == .disconnected, let name = lastMacName,
              let match = discovered.first(where: { Self.name(of: $0) == name }) else { return }
        connect(to: match)
    }

    static func name(of result: NWBrowser.Result) -> String? {
        if case .service(let name, _, _, _) = result.endpoint { return name }
        return nil
    }

    /// Try a saved token first; fall back to asking the user for the PIN.
    func authenticate(pin: String?) async {
        let token = pin == nil ? savedToken : nil
        if pin == nil && token == nil { state = .needsPIN; return }
        switch await send(.pair(pin: pin, token: token)) {
        case .paired(let newToken, let macName):
            savedToken = newToken
            if case .service(let name, _, _, _)? = currentEndpoint { lastMacName = name }
            state = .connected(macName: macName)
            await refreshApps()
        case .unauthorized:
            savedToken = nil
            state = .needsPIN
            if pin != nil { lastError = "Wrong PIN" }
        case .error(let message):
            lastError = message
        default: break
        }
    }

    func refreshApps() async {
        if case .apps(let list) = await send(.listApps) { apps = list }
    }

    /// Fire-and-forget convenience for tile taps.
    func run(_ command: DockCommand) {
        Task {
            if case .error(let message) = await send(command) { lastError = message }
        }
    }

    // MARK: Wire

    func send(_ command: DockCommand) async -> DockResponse {
        guard let connection, let data = try? Framing.encode(command) else {
            return .error("Not connected")
        }
        return await withCheckedContinuation { continuation in
            pending.append(continuation)
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    Task { @MainActor in self?.resolveNext(with: .error(error.localizedDescription)) }
                }
            })
        }
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if let data {
                    self.buffer.append(data)
                    while let (response, consumed) = try? Framing.decode(DockResponse.self, from: self.buffer) {
                        self.buffer.removeFirst(consumed)
                        self.resolveNext(with: response)
                    }
                }
                if isComplete || error != nil {
                    self.disconnect()
                    self.autoConnectIfPossible()
                    return
                }
                self.receive()
            }
        }
    }

    private func resolveNext(with response: DockResponse) {
        guard !pending.isEmpty else { return }
        pending.removeFirst().resume(returning: response)
    }

    // MARK: Persistence

    private var tokenKey: String {
        // One token per Mac, keyed by its Bonjour name.
        if case .service(let name, _, _, _)? = currentEndpoint { return "token.\(name)" }
        return "token.default"
    }

    private var lastMacName: String? {
        get { UserDefaults.standard.string(forKey: "lastMacName") }
        set { UserDefaults.standard.set(newValue, forKey: "lastMacName") }
    }

    private var savedToken: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }
}
