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
    case invalidEndpoint
}

protocol ConnectionManaging: AnyObject {
    var state: ConnectionState { get }
    var messages: [ChatMessage] { get }
    var pendingApproval: Mrt_ApprovalRequest? { get }
    var sessions: [SessionModel] { get }
    var onStateChange: ((ConnectionState) -> Void)? { get set }
    var onMessagesChange: (([ChatMessage]) -> Void)? { get set }
    var onPendingApprovalChange: ((Mrt_ApprovalRequest?) -> Void)? { get set }
    var onSessionsChange: (([SessionModel]) -> Void)? { get set }

    func connect(host: String, port: Int) async throws
    func disconnect()
    func sendPrompt(_ prompt: String, sessionID: String) async throws
    func respondToApproval(_ approvalID: String, approved: Bool) async throws
    func cancelTask(sessionID: String) async throws
    func switchSession(to sessionID: String) async throws
    func createSession(name: String, workingDirectory: String) async throws
}

extension ConnectionManaging {
    func cancelTask(sessionID: String) async throws {
    }

    func switchSession(to sessionID: String) async throws {
    }
}

final class ConnectionManager: ConnectionManaging {
    private static let reconnectRetryDelay: TimeInterval = 0.5

    private let socket: WebSocketClientProtocol
    private let heartbeatInterval: TimeInterval
    private let timeoutInterval: TimeInterval
    private let dispatcher = MessageDispatcher()
    private enum TransportMode {
        case direct
        case managed
    }
    private struct NodeRegistration {
        let authToken: String
        let deviceID: String
        let displayName: String
    }

    private(set) var state: ConnectionState = .disconnected {
        didSet { onStateChange?(state) }
    }
    private(set) var messages: [ChatMessage] = [] {
        didSet { onMessagesChange?(messages) }
    }
    private(set) var pendingApproval: Mrt_ApprovalRequest? {
        didSet { onPendingApprovalChange?(pendingApproval) }
    }
    private(set) var sessions: [SessionModel] = [] {
        didSet { onSessionsChange?(sessions) }
    }
    private(set) var devices: [Mrt_DeviceInfo] = [] {
        didSet { onDevicesChange?(devices) }
    }

    var onStateChange: ((ConnectionState) -> Void)? {
        didSet { onStateChange?(state) }
    }
    var onMessagesChange: (([ChatMessage]) -> Void)? {
        didSet { onMessagesChange?(messages) }
    }
    var onPendingApprovalChange: ((Mrt_ApprovalRequest?) -> Void)? {
        didSet { onPendingApprovalChange?(pendingApproval) }
    }
    var onSessionsChange: (([SessionModel]) -> Void)? {
        didSet { onSessionsChange?(sessions) }
    }
    var onDevicesChange: (([Mrt_DeviceInfo]) -> Void)? {
        didSet { onDevicesChange?(devices) }
    }

    private var heartbeatTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var handshakeSucceeded = false
    private var nodeRegistrationSucceeded = false
    private var lastInboundMessageAt: Date?
    private var endpointURL: URL?
    private var connectionAttemptID = UUID()
    private var transportMode: TransportMode = .direct
    private var nodeRegistration: NodeRegistration?
    private var pendingTargetDeviceID: String?

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
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmedHost.isEmpty,
            !trimmedHost.contains("://"),
            let url = URL(string: "ws://\(trimmedHost):\(port)/")
        else {
            throw ConnectionManagerError.invalidEndpoint
        }
        endpointURL = url
        transportMode = .direct
        nodeRegistration = nil
        pendingTargetDeviceID = nil
        connectionAttemptID = UUID()
        reconnectTask?.cancel()
        reconnectTask = nil
        do {
            try await establishConnection(to: url, connectionState: .connecting, attemptID: connectionAttemptID)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            transitionToReconnecting()
        }
    }

    func connectManaged(
        nodeURL: String,
        authToken: String,
        deviceID: String,
        displayName: String,
        targetDeviceID: String? = nil
    ) async throws {
        let trimmedURL = nodeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), ["ws", "wss"].contains(url.scheme?.lowercased()) else {
            throw ConnectionManagerError.invalidEndpoint
        }

        endpointURL = url
        transportMode = .managed
        nodeRegistration = NodeRegistration(
            authToken: authToken.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceID: deviceID.trimmingCharacters(in: .whitespacesAndNewlines),
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        pendingTargetDeviceID = targetDeviceID
        connectionAttemptID = UUID()
        reconnectTask?.cancel()
        reconnectTask = nil

        do {
            try await establishManagedConnection(
                to: url,
                registration: nodeRegistration!,
                connectionState: .connecting,
                attemptID: connectionAttemptID
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            transitionToReconnecting()
        }
    }

    func disconnect() {
        endpointURL = nil
        nodeRegistration = nil
        pendingTargetDeviceID = nil
        connectionAttemptID = UUID()
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

    func respondToApproval(_ approvalID: String, approved: Bool) async throws {
        guard handshakeSucceeded else {
            throw ConnectionManagerError.notConnected
        }

        var command = Mrt_AgentCommand()
        command.approvalResponse = .with { response in
            response.approvalID = approvalID
            response.approved = approved
        }

        dispatcher.clearPendingApproval()
        syncDispatcherOutputs()

        try await sendEnvelope(makeEnvelope { envelope in
            envelope.command = command
        })
    }

    func cancelTask(sessionID: String) async throws {
        guard handshakeSucceeded else {
            throw ConnectionManagerError.notConnected
        }

        var command = Mrt_AgentCommand()
        command.cancelTask = .with { cancel in
            cancel.sessionID = sessionID
        }

        try await sendEnvelope(makeEnvelope { envelope in
            envelope.command = command
        })
    }

    func switchSession(to sessionID: String) async throws {
        guard handshakeSucceeded else {
            throw ConnectionManagerError.notConnected
        }

        var sessionControl = Mrt_SessionControl()
        sessionControl.switchTo = .with { switchRequest in
            switchRequest.sessionID = sessionID
        }

        try await sendEnvelope(makeEnvelope { envelope in
            envelope.session = sessionControl
        })
    }

    func createSession(name: String, workingDirectory: String) async throws {
        guard handshakeSucceeded else {
            throw ConnectionManagerError.notConnected
        }

        var control = Mrt_SessionControl()
        control.create = .with { create in
            create.name = name
            create.workingDir = workingDirectory
        }

        try await sendEnvelope(makeEnvelope { envelope in
            envelope.session = control
        })
    }

    func requestDeviceList() async throws {
        guard nodeRegistrationSucceeded else {
            throw ConnectionManagerError.notConnected
        }

        try await sendEnvelope(makeEnvelope { envelope in
            envelope.deviceListRequest = Mrt_DeviceListRequest()
        })
    }

    func connectToDevice(targetDeviceID: String) async throws {
        guard nodeRegistrationSucceeded else {
            throw ConnectionManagerError.notConnected
        }

        try await sendEnvelope(makeEnvelope { envelope in
            envelope.connectToDevice = .with { request in
                request.targetDeviceID = targetDeviceID
            }
        })
    }

    private func handleIncomingData(_ data: Data, attemptID: UUID) {
        synchronizeOnMain {
            guard attemptID == self.connectionAttemptID else {
                return
            }

            guard let envelope = try? ProtobufCodec.decode(data) else {
                return
            }

            guard attemptID == self.connectionAttemptID else {
                return
            }

            self.lastInboundMessageAt = Date()

            switch envelope.payload {
            case .event(let event):
                switch event.evt {
                case .agentInfo:
                    guard attemptID == self.connectionAttemptID else { return }
                    guard !self.handshakeSucceeded else { return }
                    self.handshakeSucceeded = true
                    self.state = .connected
                    self.lastInboundMessageAt = Date()
                    self.startHeartbeatLoop()
                    self.startInboundTimeoutLoop(attemptID: attemptID)
                case .approvalRequest:
                    self.state = .showingApproval
                case .statusUpdate(let update):
                    switch update.status {
                    case .running:
                        self.state = .loading
                    case .waitingApproval:
                        self.state = .showingApproval
                    case .completed, .cancelled, .error, .idle:
                        self.state = .connected
                    case .unspecified, .UNRECOGNIZED:
                        break
                    }
                case .error(let error):
                    if error.fatal {
                        self.transitionToReconnecting()
                    }
                case .codexOutput, .sessionList, .none:
                    break
                }
            case .deviceRegisterAck(let ack):
                self.nodeRegistrationSucceeded = ack.success
                if ack.success, let pendingTargetDeviceID = self.pendingTargetDeviceID {
                    self.state = .connecting
                    Task { try? await self.connectToDevice(targetDeviceID: pendingTargetDeviceID) }
                } else {
                    self.state = ack.success ? .connected : .disconnected
                }
            case .deviceListResponse(let response):
                self.devices = response.devices
            case .connectToDeviceAck(let ack):
                if ack.success {
                    self.state = .connecting
                    Task {
                        try? await self.sendEnvelope(self.makeHandshakeEnvelope())
                    }
                    self.startHandshakeTimeoutLoop(attemptID: attemptID)
                } else {
                    self.state = .connected
                }
            default:
                return
            }

            self.dispatcher.apply(envelope)
            self.syncDispatcherOutputs()
        }
    }

    private func establishConnection(to url: URL, connectionState: ConnectionState, attemptID: UUID) async throws {
        try ensureActiveAttempt(attemptID)
        teardownSocket()
        try ensureActiveAttempt(attemptID)
        configureSocketCallbacks(attemptID: attemptID)
        state = connectionState
        try ensureActiveAttempt(attemptID)
        try await socket.connect(url: url)
        try ensureActiveAttempt(attemptID)
        try await sendEnvelope(makeHandshakeEnvelope())
        startHandshakeTimeoutLoop(attemptID: attemptID)
    }

    private func establishManagedConnection(
        to url: URL,
        registration: NodeRegistration,
        connectionState: ConnectionState,
        attemptID: UUID
    ) async throws {
        try ensureActiveAttempt(attemptID)
        teardownSocket()
        try ensureActiveAttempt(attemptID)
        configureSocketCallbacks(attemptID: attemptID)
        state = connectionState
        try ensureActiveAttempt(attemptID)
        try await socket.connect(url: url)
        try ensureActiveAttempt(attemptID)
        try await sendEnvelope(makeEnvelope { envelope in
            envelope.deviceRegister = .with { register in
                register.deviceID = registration.deviceID
                register.authToken = registration.authToken
                register.deviceType = .phone
                register.displayName = registration.displayName
                register.agentVersion = "1.0.0"
            }
        })
    }

    private func configureSocketCallbacks(attemptID: UUID) {
        socket.onReceive = { [weak self] data in
            self?.handleIncomingData(data, attemptID: attemptID)
        }
        socket.onClose = { [weak self] in
            self?.handleSocketClose(attemptID: attemptID)
        }
    }

    private func handleSocketClose(attemptID: UUID) {
        synchronizeOnMain {
            guard attemptID == self.connectionAttemptID else {
                return
            }
            self.transitionToReconnecting()
        }
    }

    private func startHeartbeatLoop() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.nanoseconds(from: self.heartbeatInterval))
                guard !Task.isCancelled else { return }
                let shouldSendHeartbeat = self.readOnMain { self.handshakeSucceeded }
                guard shouldSendHeartbeat else { return }

                var heartbeat = Mrt_Envelope()
                heartbeat.protocolVersion = 1
                heartbeat.requestID = UUID().uuidString
                heartbeat.timestampMs = Self.nowMilliseconds()
                heartbeat.heartbeat = Mrt_Heartbeat()
                try? await self.socket.send(ProtobufCodec.encode(heartbeat))
            }
        }
    }

    private func startHandshakeTimeoutLoop(attemptID: UUID) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            let pollInterval = min(max(self.timeoutInterval / 4, 0.01), self.timeoutInterval)
            let startedAt = Date()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.nanoseconds(from: pollInterval))
                guard !Task.isCancelled else { return }

                let shouldReconnect = self.readOnMain {
                    guard attemptID == self.connectionAttemptID else { return false }
                    guard !self.handshakeSucceeded else { return false }
                    return Date().timeIntervalSince(startedAt) > self.timeoutInterval
                }

                if shouldReconnect {
                    self.transitionToReconnecting()
                    return
                }
            }
        }
    }

    private func startInboundTimeoutLoop(attemptID: UUID) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            let pollInterval = min(max(self.timeoutInterval / 4, 0.01), self.timeoutInterval)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.nanoseconds(from: pollInterval))
                guard !Task.isCancelled else { return }

                let shouldReconnect = self.readOnMain {
                    guard attemptID == self.connectionAttemptID else { return false }
                    guard let lastInboundMessageAt = self.lastInboundMessageAt else { return false }
                    return Date().timeIntervalSince(lastInboundMessageAt) > self.timeoutInterval
                }

                if shouldReconnect {
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
        synchronizeOnMain {
            guard self.state != .disconnected else { return }
            self.state = .reconnecting
            self.teardownSocket()

            guard self.reconnectTask == nil, let endpointURL = self.endpointURL else {
                return
            }

            let attemptID = UUID()
            self.connectionAttemptID = attemptID
            self.reconnectTask = Task { [weak self] in
                guard let self else { return }
                var shouldRetry = false
                defer {
                    self.reconnectTask = nil
                    if shouldRetry {
                        self.scheduleReconnectRetry()
                    }
                }

                do {
                    try self.ensureActiveAttempt(attemptID)
                    switch self.transportMode {
                    case .direct:
                        try await self.establishConnection(to: endpointURL, connectionState: .reconnecting, attemptID: attemptID)
                    case .managed:
                        guard let registration = self.nodeRegistration else { return }
                        try await self.establishManagedConnection(
                            to: endpointURL,
                            registration: registration,
                            connectionState: .reconnecting,
                            attemptID: attemptID
                        )
                    }
                } catch is CancellationError {
                } catch {
                    shouldRetry = true
                }
            }
        }
   }

    private func scheduleReconnectRetry() {
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.nanoseconds(from: Self.reconnectRetryDelay))
            self.transitionToReconnecting()
        }
    }

    private func teardownSocket() {
        heartbeatTask?.cancel()
        timeoutTask?.cancel()
        heartbeatTask = nil
        timeoutTask = nil
        handshakeSucceeded = false
        nodeRegistrationSucceeded = false
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

    private func ensureActiveAttempt(_ attemptID: UUID) throws {
        try Task.checkCancellation()
        guard attemptID == connectionAttemptID else {
            throw CancellationError()
        }
    }

    private func syncDispatcherOutputs() {
        let dispatcherState = dispatcher.state
        if dispatcherState != .disconnected || state == .disconnected {
            state = dispatcherState
        }
        messages = dispatcher.messages
        pendingApproval = dispatcher.pendingApproval
        sessions = dispatcher.sessions
    }

    private func synchronizeOnMain(_ work: () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    private func readOnMain<T>(_ work: () -> T) -> T {
        if Thread.isMainThread {
            return work()
        }
        return DispatchQueue.main.sync(execute: work)
    }
}
