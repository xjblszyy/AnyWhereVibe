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

    func testConnectionManagerRejectsInvalidHostBeforeConnecting() async {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 15, timeoutInterval: 45)

        do {
            try await manager.connect(host: "ws://127.0.0.1", port: 9876)
            XCTFail("expected invalid endpoint error")
        } catch let error as ConnectionManagerError {
            XCTAssertEqual(error, .invalidEndpoint)
        } catch {
            XCTFail("unexpected error: \(error)")
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

    func testConnectionManagerKeepsRetryingAfterRepeatedHandshakeTimeoutsWhileReconnecting() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 0.1, timeoutInterval: 0.02)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        try await Task.sleep(nanoseconds: 90_000_000)

        XCTAssertGreaterThanOrEqual(socket.connectCalls.count, 3)
        XCTAssertEqual(manager.state, .reconnecting)
        XCTAssertGreaterThanOrEqual(socket.sentData.count, 3)
    }

    func testConnectionManagerInitialConnectFailureTransitionsIntoReconnectRetries() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 0.1, timeoutInterval: 0.02)
        socket.connectErrors = [
            StubWebSocketClient.StubError.connectFailed,
            StubWebSocketClient.StubError.connectFailed,
        ]

        try await manager.connect(host: "127.0.0.1", port: 9876)
        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertGreaterThanOrEqual(socket.connectCalls.count, 2)
        XCTAssertEqual(manager.state, .reconnecting)
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

    func testConnectionManagerClearsLoadingStateOnNonFatalErrorEvent() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 15, timeoutInterval: 45)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())

        try await manager.sendPrompt("hello", sessionID: "session-1")
        XCTAssertEqual(manager.state, .loading)

        socket.pushIncomingEnvelope(makeErrorEnvelope(message: "Temporary failure", fatal: false))

        XCTAssertEqual(manager.state, .connected)
        XCTAssertEqual(manager.messages.last?.content, "Temporary failure")
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

    func testConnectionManagerSendsCloseSessionControl() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 15, timeoutInterval: 45)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())

        try await manager.closeSession(id: "session-1")

        let closeEnvelope = try ProtobufCodec.decode(socket.sentData.last!)
        if case .session(let session) = closeEnvelope.payload,
           case .close(let close)? = session.action {
            XCTAssertEqual(close.sessionID, "session-1")
        } else {
            XCTFail("Expected close session envelope")
        }
    }

    func testConnectionManagerSendsCancelTaskCommand() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 15, timeoutInterval: 45)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())

        try await manager.cancelTask(sessionID: "session-1")

        let cancelEnvelope = try ProtobufCodec.decode(socket.sentData.last!)
        if case .command(let command) = cancelEnvelope.payload,
           case .cancelTask(let cancel)? = command.cmd {
            XCTAssertEqual(cancel.sessionID, "session-1")
        } else {
            XCTFail("Expected cancel task command envelope")
        }
    }

    func testConnectionManagerSendsGitStatusOperation() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 15, timeoutInterval: 45)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())

        let requestID = try await manager.requestGitStatus(sessionID: "session-1")

        let gitEnvelope = try ProtobufCodec.decode(socket.sentData.last!)
        XCTAssertEqual(gitEnvelope.requestID, requestID)
        if case .gitOp(let operation) = gitEnvelope.payload,
           case .status = operation.op {
            XCTAssertEqual(operation.sessionID, "session-1")
        } else {
            XCTFail("Expected git status envelope")
        }
    }

    func testConnectionManagerSendsGitDiffOperation() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 15, timeoutInterval: 45)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())

        let requestID = try await manager.requestGitDiff(sessionID: "session-1", path: "Sources/App.swift")

        let gitEnvelope = try ProtobufCodec.decode(socket.sentData.last!)
        XCTAssertEqual(gitEnvelope.requestID, requestID)
        if case .gitOp(let operation) = gitEnvelope.payload,
           case .diff(let diff)? = operation.op {
            XCTAssertEqual(operation.sessionID, "session-1")
            XCTAssertEqual(diff.path, "Sources/App.swift")
            XCTAssertFalse(diff.staged)
        } else {
            XCTFail("Expected git diff envelope")
        }
    }

    func testConnectionManagerSendsListDirOperation() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 15, timeoutInterval: 45)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())

        let requestID = try await manager.listDirectory(sessionID: "session-1", path: "")

        let fileEnvelope = try ProtobufCodec.decode(socket.sentData.last!)
        XCTAssertEqual(fileEnvelope.requestID, requestID)
        if case .fileOp(let operation) = fileEnvelope.payload,
           case .listDir(let listDir)? = operation.op {
            XCTAssertEqual(operation.sessionID, "session-1")
            XCTAssertEqual(listDir.path, "")
            XCTAssertFalse(listDir.recursive)
        } else {
            XCTFail("Expected file list envelope")
        }
    }

    func testConnectionManagerSendsReadFileOperation() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 15, timeoutInterval: 45)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())

        let requestID = try await manager.readFile(sessionID: "session-1", path: "notes.txt")

        let fileEnvelope = try ProtobufCodec.decode(socket.sentData.last!)
        XCTAssertEqual(fileEnvelope.requestID, requestID)
        if case .fileOp(let operation) = fileEnvelope.payload,
           case .readFile(let readFile)? = operation.op {
            XCTAssertEqual(operation.sessionID, "session-1")
            XCTAssertEqual(readFile.path, "notes.txt")
            XCTAssertEqual(readFile.offset, 0)
            XCTAssertEqual(readFile.length, 0)
        } else {
            XCTFail("Expected file read envelope")
        }
    }

    func testConnectionManagerSendsCreateDeleteRenameOperations() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 15, timeoutInterval: 45)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())

        _ = try await manager.createFile(sessionID: "session-1", path: "new.txt")
        _ = try await manager.createDirectory(sessionID: "session-1", path: "folder")
        _ = try await manager.deletePath(sessionID: "session-1", path: "new.txt", recursive: false)
        _ = try await manager.renamePath(sessionID: "session-1", fromPath: "folder", toPath: "renamed")

        let createFileEnvelope = try ProtobufCodec.decode(socket.sentData[1])
        let createDirEnvelope = try ProtobufCodec.decode(socket.sentData[2])
        let deleteEnvelope = try ProtobufCodec.decode(socket.sentData[3])
        let renameEnvelope = try ProtobufCodec.decode(socket.sentData[4])

        if case .fileOp(let operation) = createFileEnvelope.payload,
           case .createFile(let createFile)? = operation.op {
            XCTAssertEqual(createFile.path, "new.txt")
        } else {
            XCTFail("Expected create file envelope")
        }

        if case .fileOp(let operation) = createDirEnvelope.payload,
           case .createDir(let createDir)? = operation.op {
            XCTAssertEqual(createDir.path, "folder")
        } else {
            XCTFail("Expected create dir envelope")
        }

        if case .fileOp(let operation) = deleteEnvelope.payload,
           case .deletePath(let deletePath)? = operation.op {
            XCTAssertEqual(deletePath.path, "new.txt")
            XCTAssertFalse(deletePath.recursive)
        } else {
            XCTFail("Expected delete path envelope")
        }

        if case .fileOp(let operation) = renameEnvelope.payload,
           case .renamePath(let renamePath)? = operation.op {
            XCTAssertEqual(renamePath.fromPath, "folder")
            XCTAssertEqual(renamePath.toPath, "renamed")
        } else {
            XCTFail("Expected rename path envelope")
        }
    }

    func testConnectionManagerRegistersPhoneInManagedMode() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 15, timeoutInterval: 45)

        try await manager.connectManaged(
            nodeURL: "ws://relay.example.com/ws",
            authToken: "mrt_ak_example1234567890",
            deviceID: "iphone-1",
            displayName: "iPhone 1"
        )

        XCTAssertEqual(socket.connectedURL?.absoluteString, "ws://relay.example.com/ws")
        let registerEnvelope = try ProtobufCodec.decode(socket.sentData[0])
        if case .deviceRegister = registerEnvelope.payload {
        } else {
            XCTFail("Expected device register envelope")
        }

        socket.pushIncomingEnvelope(makeDeviceRegisterAckEnvelope(success: true))

        XCTAssertEqual(manager.state, .connected)
    }

    func testConnectionManagerPublishesManagedDeviceList() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 15, timeoutInterval: 45)

        try await manager.connectManaged(
            nodeURL: "ws://relay.example.com/ws",
            authToken: "mrt_ak_example1234567890",
            deviceID: "iphone-1",
            displayName: "iPhone 1"
        )
        socket.pushIncomingEnvelope(makeDeviceRegisterAckEnvelope(success: true))

        try await manager.requestDeviceList()

        let requestEnvelope = try ProtobufCodec.decode(socket.sentData.last!)
        if case .deviceListRequest = requestEnvelope.payload {
        } else {
            XCTFail("Expected device list request envelope")
        }

        socket.pushIncomingEnvelope(makeDeviceListResponseEnvelope())

        XCTAssertEqual(manager.devices.map(\.deviceID), ["agent-1"])
    }

    func testConnectionManagerConnectToDeviceSendsHandshakeAndTransitionsToAgentConnected() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 15, timeoutInterval: 45)

        try await manager.connectManaged(
            nodeURL: "ws://relay.example.com/ws",
            authToken: "mrt_ak_example1234567890",
            deviceID: "iphone-1",
            displayName: "iPhone 1"
        )
        socket.pushIncomingEnvelope(makeDeviceRegisterAckEnvelope(success: true))

        try await manager.connectToDevice(targetDeviceID: "agent-1")

        let connectEnvelope = try ProtobufCodec.decode(socket.sentData.last!)
        if case .connectToDevice = connectEnvelope.payload {
        } else {
            XCTFail("Expected connect-to-device envelope")
        }

        socket.pushIncomingEnvelope(makeConnectToDeviceAckEnvelope(success: true))
        try await Task.sleep(nanoseconds: 10_000_000)

        let handshakeEnvelope = try ProtobufCodec.decode(socket.sentData.last!)
        if case .handshake = handshakeEnvelope.payload {
        } else {
            XCTFail("Expected handshake envelope")
        }

        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())

        XCTAssertEqual(manager.state, .connected)
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
