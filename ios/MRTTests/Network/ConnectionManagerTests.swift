@testable import MRT
import XCTest

final class ConnectionManagerTests: XCTestCase {
    func testConnectionManagerConnectsToSocketURLSendsHandshakeAndWaitsForAgentInfo() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 15, timeoutInterval: 45)

        try await manager.connect(host: "127.0.0.1", port: 9876)

        XCTAssertEqual(socket.connectedURL?.absoluteString, "ws://127.0.0.1:9876/")
        XCTAssertEqual(manager.state, .connecting)
        XCTAssertEqual(socket.sentData.count, 1)
        let handshake = try ProtobufCodec.decode(socket.sentData[0])
        if case .handshake = handshake.payload {
        } else {
            XCTFail("Expected handshake envelope")
        }

        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())

        XCTAssertEqual(manager.state, .connected)
    }

    func testConnectionManagerReconnectsOnSocketClose() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 0.1, timeoutInterval: 45)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())

        socket.simulateClose()

        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(socket.connectCalls.count, 2)
        XCTAssertEqual(socket.connectCalls.last?.absoluteString, "ws://127.0.0.1:9876/")
        XCTAssertEqual(manager.state, .reconnecting)
        XCTAssertEqual(socket.sentData.count, 2)
        let reconnectHandshake = try ProtobufCodec.decode(socket.sentData[1])
        if case .handshake = reconnectHandshake.payload {
        } else {
            XCTFail("Expected reconnect handshake envelope")
        }
    }

    func testConnectionManagerSendsHeartbeatEnvelopeAfterHandshakeSuccess() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 0.01, timeoutInterval: 0.05)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())

        try await Task.sleep(nanoseconds: 25_000_000)

        XCTAssertTrue(socket.sentData.dropFirst().contains(where: { data in
            guard let envelope = try? ProtobufCodec.decode(data) else {
                return false
            }
            if case .heartbeat = envelope.payload {
                return true
            }
            return false
        }))
    }

    func testConnectionManagerReconnectsAfterInboundTimeout() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 0.05, timeoutInterval: 0.02)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())

        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(socket.connectCalls.count, 2)
        XCTAssertEqual(manager.state, .reconnecting)
        XCTAssertEqual(socket.sentData.count, 2)
        let reconnectHandshake = try ProtobufCodec.decode(socket.sentData[1])
        if case .handshake = reconnectHandshake.payload {
        } else {
            XCTFail("Expected reconnect handshake envelope")
        }
    }

    func testConnectionManagerRejectsPromptSendBeforeHandshakeSuccess() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 15, timeoutInterval: 45)

        try await manager.connect(host: "127.0.0.1", port: 9876)

        await XCTAssertThrowsErrorAsync {
            try await manager.sendPrompt("hello", sessionID: "session-1")
        }

        XCTAssertEqual(socket.sentData.count, 1)
        let firstEnvelope = try ProtobufCodec.decode(socket.sentData[0])
        if case .handshake = firstEnvelope.payload {
        } else {
            XCTFail("Expected handshake envelope")
        }
    }

    func testConnectionManagerCancelledReconnectDoesNotResurrectAfterDisconnect() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 0.1, timeoutInterval: 45)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())
        socket.nextConnectDelayNanoseconds = 1_000_000_000

        socket.simulateClose()
        try await Task.sleep(nanoseconds: 20_000_000)
        manager.disconnect()
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(manager.state, .disconnected)
        XCTAssertEqual(socket.connectCalls.count, 2)
        XCTAssertEqual(socket.sentData.count, 1)
    }

    func testConnectionManagerCancelledReconnectDoesNotResurrectAfterNewConnect() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 0.1, timeoutInterval: 45)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())
        socket.nextConnectDelayNanoseconds = 1_000_000_000

        socket.simulateClose()
        try await Task.sleep(nanoseconds: 20_000_000)
        try await manager.connect(host: "127.0.0.1", port: 9999)
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(manager.state, .connecting)
        XCTAssertEqual(socket.connectCalls.count, 3)
        XCTAssertEqual(socket.connectCalls.last?.absoluteString, "ws://127.0.0.1:9999/")
        XCTAssertEqual(socket.sentData.count, 2)
        let replacementHandshake = try ProtobufCodec.decode(socket.sentData[1])
        if case .handshake = replacementHandshake.payload {
        } else {
            XCTFail("Expected replacement handshake envelope")
        }
    }

    func testConnectionManagerReconnectsWhenHandshakeTimesOutWaitingForAgentInfo() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 0.1, timeoutInterval: 0.02)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(manager.state, .reconnecting)
        XCTAssertEqual(socket.connectCalls.count, 2)
        XCTAssertEqual(socket.sentData.count, 2)
        let reconnectHandshake = try ProtobufCodec.decode(socket.sentData[1])
        if case .handshake = reconnectHandshake.payload {
        } else {
            XCTFail("Expected reconnect handshake envelope after handshake timeout")
        }
    }

    func testConnectionManagerIgnoresStaleReceiveCallbackAfterReplacementConnect() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 15, timeoutInterval: 45)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        let staleReceive = try XCTUnwrap(socket.receiveCallbackHistory.last)

        try await manager.connect(host: "127.0.0.1", port: 9999)
        staleReceive(try ProtobufCodec.encode(makeAgentInfoEnvelope()))

        XCTAssertEqual(manager.state, .connecting)
        XCTAssertEqual(socket.connectCalls.count, 2)
        XCTAssertEqual(socket.connectCalls.last?.absoluteString, "ws://127.0.0.1:9999/")
    }

    func testConnectionManagerIgnoresStaleCloseCallbackAfterReplacementConnect() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 15, timeoutInterval: 45)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        let staleClose = try XCTUnwrap(socket.closeCallbackHistory.last)

        try await manager.connect(host: "127.0.0.1", port: 9999)
        staleClose()
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(manager.state, .connecting)
        XCTAssertEqual(socket.connectCalls.count, 2)
        XCTAssertEqual(socket.connectCalls.last?.absoluteString, "ws://127.0.0.1:9999/")
    }

    func testConnectionManagerIgnoresLateInboundMessagesAfterTransitioningToReconnect() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 0.1, timeoutInterval: 45)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())
        let staleReceive = try XCTUnwrap(socket.receiveCallbackHistory.last)
        socket.nextConnectDelayNanoseconds = 1_000_000_000

        socket.simulateClose()
        try await Task.sleep(nanoseconds: 20_000_000)
        staleReceive(try ProtobufCodec.encode(makeAgentInfoEnvelope()))

        XCTAssertEqual(manager.state, .reconnecting)
        XCTAssertEqual(socket.sentData.count, 1)
    }

    func testConnectionManagerPublishesInboundDispatcherState() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 15, timeoutInterval: 45)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())
        socket.pushIncomingEnvelope(makeCodexOutput(content: "Hello ", complete: false))
        socket.pushIncomingEnvelope(makeCodexOutput(content: "world", complete: true))
        socket.pushIncomingEnvelope(makeApprovalRequestEnvelope())
        socket.pushIncomingEnvelope(makeSessionListEnvelope())

        XCTAssertEqual(manager.messages.last?.content, "Hello world")
        XCTAssertEqual(manager.messages.last?.isComplete, true)
        XCTAssertEqual(manager.pendingApproval?.approvalID, "approval-1")
        XCTAssertEqual(manager.sessions.map(\.id), ["session-1"])
    }

    func testConnectionManagerSendsApprovalResponsesAndCreateSessionCommands() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 15, timeoutInterval: 45)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())
        socket.pushIncomingEnvelope(makeApprovalRequestEnvelope())

        try await manager.respondToApproval("approval-1", approved: true)
        try await manager.createSession(name: "Daily", workingDirectory: "/tmp/daily")

        let approvalEnvelope = try ProtobufCodec.decode(socket.sentData[1])
        let createEnvelope = try ProtobufCodec.decode(socket.sentData[2])

        if case .command(let command) = approvalEnvelope.payload,
           case .approvalResponse(let response)? = command.cmd {
            XCTAssertEqual(response.approvalID, "approval-1")
            XCTAssertTrue(response.approved)
        } else {
            XCTFail("Expected approval response command envelope")
        }

        if case .session(let session) = createEnvelope.payload,
           case .create(let create)? = session.action {
            XCTAssertEqual(create.name, "Daily")
            XCTAssertEqual(create.workingDir, "/tmp/daily")
        } else {
            XCTFail("Expected create session envelope")
        }
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @escaping () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
    }
}
