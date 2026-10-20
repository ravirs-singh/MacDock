import Foundation
import Network
import MacDockProtocol

/// Listens on the LAN, advertises over Bonjour, and dispatches commands.
@MainActor
final class DockServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var pin: String = ""
    @Published private(set) var pairedTokens: Set<String> = []

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: ClientConnection] = [:]
    private let executor = CommandExecutor()
    private let input = InputController()
    private let tokensKey = "pairedTokens"

    init() {
        pairedTokens = Set(UserDefaults.standard.stringArray(forKey: tokensKey) ?? [])
        regeneratePIN()
        start()
    }

    func regeneratePIN() {
        pin = String(format: "%06d", Int.random(in: 0 ..< 1_000_000))
    }

    func forgetAll() {
        pairedTokens = []
        persistTokens()
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            let listener = try NWListener(using: params)
            listener.service = NWListener.Service(
                name: Host.current().localizedName ?? "Mac",
                type: macDockServiceType
            )
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.isRunning = (state == .ready)
                    if case .failed(let error) = state {
                        NSLog("Listener failed: \(error). Restarting.")
                        self?.listener?.cancel()
                        self?.start()
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            NSLog("Could not create listener: \(error)")
        }
    }

    private func accept(_ nwConnection: NWConnection) {
        let client = ClientConnection(nwConnection) { [weak self] command, client in
            guard let self else { return .error("Server gone") }
            return await self.handle(command, from: client)
        } onClose: { [weak self] client in
            self?.connections.removeValue(forKey: ObjectIdentifier(client))
        }
        connections[ObjectIdentifier(client)] = client
        client.start()
    }

    private func handle(_ command: DockCommand, from client: ClientConnection) async -> DockResponse? {
        // Every connection must authenticate first.
        if case .pair(let pin, let token) = command {
            if let token, pairedTokens.contains(token) {
                client.isAuthenticated = true
                return .paired(token: token, macName: Host.current().localizedName ?? "Mac")
            }
            if let pin, pin == self.pin {
                let newToken = UUID().uuidString
                pairedTokens.insert(newToken)
                persistTokens()
                regeneratePIN() // one PIN per pairing
                client.isAuthenticated = true
                return .paired(token: newToken, macName: Host.current().localizedName ?? "Mac")
            }
            return .unauthorized
        }
        guard client.isAuthenticated else { return .unauthorized }
        if command.isFireAndForget {
            input.handle(command)
            return nil
        }
        return await executor.execute(command)
    }

    private func persistTokens() {
        UserDefaults.standard.set(Array(pairedTokens), forKey: tokensKey)
    }
}

/// One connected iPhone.
final class ClientConnection {
    typealias Handler = (DockCommand, ClientConnection) async -> DockResponse?

    var isAuthenticated = false
    private let connection: NWConnection
    private let handler: Handler
    private let onClose: (ClientConnection) -> Void
    private var buffer = Data()

    init(_ connection: NWConnection, handler: @escaping Handler, onClose: @escaping (ClientConnection) -> Void) {
        self.connection = connection
        self.handler = handler
        self.onClose = onClose
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed, .cancelled: onClose(self)
            default: break
            }
        }
        connection.start(queue: .main)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { buffer.append(data); drainBuffer() }
            if isComplete || error != nil { connection.cancel(); return }
            receive()
        }
    }

    private func drainBuffer() {
        while let (command, consumed) = try? Framing.decode(DockCommand.self, from: buffer) {
            buffer.removeFirst(consumed)
            Task { @MainActor in
                if let response = await self.handler(command, self) { self.send(response) }
            }
        }
    }

    private func send(_ response: DockResponse) {
        guard let data = try? Framing.encode(response) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }
}
