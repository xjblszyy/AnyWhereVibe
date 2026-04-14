import Foundation

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case loading
    case showingApproval
    case reconnecting
}

enum ConnectionManagerError: Error, Equatable {
    case notConnected
}

protocol ConnectionManaging: AnyObject {
    var state: ConnectionState { get }

    func connect(host: String, port: Int) async throws
    func disconnect()
    func sendPrompt(_ prompt: String, sessionID: String) async throws
}

final class ConnectionManager: ConnectionManaging {
    private let socket: WebSocketClientProtocol
    private let heartbeatInterval: TimeInterval
    private let timeoutInterval: TimeInterval

    private(set) var state: ConnectionState = .disconnected

    private var heartbeatTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var handshakeSucceeded = false
    private var lastInboundMessageAt: Date?
    private var endpointURL: URL?

    init(
        socket: WebSocketClientProtocol = WebSocketClient(),
        heartbeatInterval: TimeInterval = 15,
        timeoutInterval: TimeInterval = 45
    ) {
        self.socket = socket
        self.heartbeatInterval = heartbeatInterval
        self.timeoutInterval = timeoutInterval
    }

    func connect(host: String, port: Int) async throws {
        let url = URL(string: "ws://\(host):\(port)/")!
        endpointURL = url
        reconnectTask?.cancel()
        reconnectTask = nil
        try await establishConnection(to: url, connectionState: .connecting)
    }

    func disconnect() {
        endpointURL = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        state = .disconnected
        teardownSocket()
    }

    func sendPrompt(_ prompt: String, sessionID: String) async throws {
        guard handshakeSucceeded else {
            throw ConnectionManagerError.notConnected
        }

        var command = Mrt_AgentCommand()
        command.sendPrompt = .with { request in
            request.sessionID = sessionID
            request.prompt = prompt
        }

        state = .loading
        try await sendEnvelope(makeEnvelope { envelope in
            envelope.command = command
        })
    }

    private func handleIncomingData(_ data: Data) {
        guard let envelope = try? ProtobufCodec.decode(data) else {
            return
        }

        lastInboundMessageAt = Date()

        guard case .event(let event)? = envelope.payload else {
            return
        }

        switch event.evt {
        case .agentInfo:
            guard !handshakeSucceeded else { return }
            handshakeSucceeded = true
            state = .connected
            lastInboundMessageAt = Date()
            startHeartbeatLoop()
            startTimeoutLoop()
        case .approvalRequest:
            state = .showingApproval
        case .statusUpdate(let update):
            switch update.status {
            case .running:
                state = .loading
            case .waitingApproval:
                state = .showingApproval
            case .completed, .cancelled, .error, .idle:
                state = .connected
            case .unspecified, .UNRECOGNIZED:
                break
            }
        case .error(let error):
            if error.fatal {
                transitionToReconnecting()
            }
        case .codexOutput, .sessionList, .none:
            break
        }
    }

    private func establishConnection(to url: URL, connectionState: ConnectionState) async throws {
        teardownSocket()
        configureSocketCallbacks()
        state = connectionState
        try await socket.connect(url: url)
        try await sendEnvelope(makeHandshakeEnvelope())
    }

    private func configureSocketCallbacks() {
        socket.onReceive = { [weak self] data in
            self?.handleIncomingData(data)
        }
        socket.onClose = { [weak self] in
            self?.transitionToReconnecting()
        }
    }

    private func startHeartbeatLoop() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.nanoseconds(from: self.heartbeatInterval))
                guard !Task.isCancelled, self.handshakeSucceeded else { return }

                var heartbeat = Mrt_Envelope()
                heartbeat.protocolVersion = 1
                heartbeat.requestID = UUID().uuidString
                heartbeat.timestampMs = Self.nowMilliseconds()
                heartbeat.heartbeat = Mrt_Heartbeat()
                try? await self.socket.send(ProtobufCodec.encode(heartbeat))
            }
        }
    }

    private func startTimeoutLoop() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            let pollInterval = min(max(self.timeoutInterval / 4, 0.01), self.timeoutInterval)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.nanoseconds(from: pollInterval))
                guard !Task.isCancelled else { return }

                if let lastInboundMessageAt = self.lastInboundMessageAt,
                   Date().timeIntervalSince(lastInboundMessageAt) > self.timeoutInterval {
                    self.transitionToReconnecting()
                    return
                }
            }
        }
    }

    private func sendEnvelope(_ envelope: Mrt_Envelope) async throws {
        try await socket.send(ProtobufCodec.encode(envelope))
    }

    private func makeHandshakeEnvelope() -> Mrt_Envelope {
        makeEnvelope { envelope in
            envelope.handshake = .with { handshake in
                handshake.protocolVersion = 1
                handshake.clientType = .phoneIos
                handshake.clientVersion = "1.0.0"
                handshake.deviceID = UUID().uuidString
            }
        }
    }

    private func makeEnvelope(configure: (inout Mrt_Envelope) -> Void) -> Mrt_Envelope {
        var envelope = Mrt_Envelope()
        envelope.protocolVersion = 1
        envelope.requestID = UUID().uuidString
        envelope.timestampMs = Self.nowMilliseconds()
        configure(&envelope)
        return envelope
    }

    private func transitionToReconnecting() {
        guard state != .disconnected else { return }
        state = .reconnecting
        heartbeatTask?.cancel()
        timeoutTask?.cancel()
        heartbeatTask = nil
        timeoutTask = nil
        handshakeSucceeded = false
        lastInboundMessageAt = nil

        guard reconnectTask == nil, let endpointURL else {
            return
        }

        reconnectTask = Task { [weak self] in
            guard let self else { return }
            defer { self.reconnectTask = nil }

            do {
                try await self.establishConnection(to: endpointURL, connectionState: .reconnecting)
            } catch {
            }
        }
    }

    private func teardownSocket() {
        heartbeatTask?.cancel()
        timeoutTask?.cancel()
        heartbeatTask = nil
        timeoutTask = nil
        handshakeSucceeded = false
        lastInboundMessageAt = nil

        socket.onReceive = nil
        socket.onClose = nil
        socket.disconnect()
    }

    private static func nowMilliseconds() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1_000)
    }

    private func nanoseconds(from interval: TimeInterval) -> UInt64 {
        UInt64(interval * 1_000_000_000)
    }
}
