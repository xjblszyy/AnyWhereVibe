@testable import MRT
import XCTest

final class ChatViewModelTests: XCTestCase {
    @MainActor
    func testConnectIfNeededRetriesWhenConfigurationChanges() async {
        let connection = StubConnectionManager()
        let viewModel = ChatViewModel(connectionManager: connection)

        await viewModel.connectIfNeeded(host: "127.0.0.1", port: 9876, mode: .direct)
        await viewModel.connectIfNeeded(host: "127.0.0.1", port: 9876, mode: .direct)
        await viewModel.connectIfNeeded(host: "127.0.0.2", port: 9876, mode: .direct)

        XCTAssertEqual(connection.connectCalls.map(\.host), ["127.0.0.1", "127.0.0.2"])
    }

    @MainActor
    func testSwitchingSessionsChangesVisibleThreadButKeepsGlobalSystemMessages() async {
        let connection = StubConnectionManager()
        let viewModel = ChatViewModel(connectionManager: connection)
        viewModel.activeSessionID = "session-1"

        connection.emitMessages([
            ChatMessage(sessionID: "session-1", content: "Session one", isComplete: true, role: .assistant),
            ChatMessage(sessionID: "session-2", content: "Session two", isComplete: true, role: .assistant),
            ChatMessage(sessionID: nil, content: "Global system note", isComplete: true, role: .system),
        ])
        await Task.yield()

        XCTAssertEqual(viewModel.messages.map(\.content), ["Session one", "Global system note"])

        viewModel.activeSessionID = "session-2"

        XCTAssertEqual(viewModel.messages.map(\.content), ["Session two", "Global system note"])
    }

    @MainActor
    func testSendPromptCreatesUserMessageAndStartsLoading() async {
        let connection = StubConnectionManager()
        let viewModel = ChatViewModel(connectionManager: connection)

        viewModel.activeSessionID = "session-1"
        viewModel.inputText = "Ship it"
        await viewModel.sendPrompt()

        XCTAssertEqual(viewModel.messages.first?.role, .user)
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertEqual(connection.sentPrompts.map(\.prompt), ["Ship it"])
    }

    @MainActor
    func testSendPromptWithoutActiveSessionDoesNothing() async {
        let connection = StubConnectionManager()
        let viewModel = ChatViewModel(connectionManager: connection)

        viewModel.activeSessionID = nil
        viewModel.inputText = "Ship it"

        await viewModel.sendPrompt()

        XCTAssertEqual(connection.sentPrompts.count, 0)
        XCTAssertEqual(viewModel.messages.count, 0)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.inputText, "Ship it")
    }

    @MainActor
    func testChatViewModelPreservesMultiTurnThreadOrderAndRemoteTimestamps() async throws {
        let connection = StubConnectionManager()
        let viewModel = ChatViewModel(connectionManager: connection)
        let assistantReplyOneID = UUID()
        let assistantReplyTwoID = UUID()

        viewModel.activeSessionID = "session-1"

        viewModel.inputText = "First prompt"
        await viewModel.sendPrompt()

        connection.emitMessages([
            ChatMessage(
                id: assistantReplyOneID,
                sessionID: "session-1",
                content: "First reply",
                isComplete: true,
                role: .assistant
            ),
        ])
        await Task.yield()

        let firstReplyTimestamp = try XCTUnwrap(
            viewModel.messages.first(where: { $0.id == assistantReplyOneID })?.timestamp
        )

        viewModel.inputText = "Second prompt"
        await viewModel.sendPrompt()

        connection.emitMessages([
            ChatMessage(
                id: assistantReplyOneID,
                sessionID: "session-1",
                content: "First reply",
                isComplete: true,
                role: .assistant
            ),
            ChatMessage(
                id: assistantReplyTwoID,
                sessionID: "session-1",
                content: "Second reply",
                isComplete: true,
                role: .assistant
            ),
        ])
        await Task.yield()

        XCTAssertEqual(
            viewModel.messages.map(\.content),
            ["First prompt", "First reply", "Second prompt", "Second reply"]
        )
        XCTAssertEqual(
            viewModel.messages.first(where: { $0.id == assistantReplyOneID })?.timestamp,
            firstReplyTimestamp
        )
    }

    @MainActor
    func testChatViewModelCoversAllRequiredUiStates() {
        let connection = StubConnectionManager()
        let viewModel = ChatViewModel(connectionManager: connection)

        viewModel.connectionState = .disconnected
        XCTAssertEqual(viewModel.connectionState, .disconnected)
        viewModel.connectionState = .connecting
        XCTAssertEqual(viewModel.connectionState, .connecting)
        viewModel.connectionState = .connected
        XCTAssertEqual(viewModel.connectionState, .connected)
        viewModel.isLoading = true
        XCTAssertTrue(viewModel.isLoading)
        viewModel.pendingApproval = makeApprovalRequest()
        XCTAssertEqual(viewModel.connectionState, .showingApproval)
        XCTAssertNotNil(viewModel.pendingApproval)
        viewModel.connectionState = .reconnecting
        XCTAssertEqual(viewModel.connectionState, .reconnecting)
    }

    @MainActor
    func testChatViewModelObservesRealConnectionManagerStateMessagesAndApprovals() async {
        let connection = StubConnectionManager()
        let viewModel = ChatViewModel(connectionManager: connection)
        let approval = makeApprovalRequest()

        viewModel.activeSessionID = "session-1"

        connection.emitState(.connecting)
        await Task.yield()
        XCTAssertEqual(viewModel.connectionState, .connecting)

        connection.emitMessages([
            ChatMessage(sessionID: "session-1", content: "Hello ", isComplete: false, role: .assistant),
            ChatMessage(sessionID: nil, content: "System note", isComplete: true, role: .system),
        ])
        await Task.yield()

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages[0].role, .assistant)
        XCTAssertEqual(viewModel.messages[0].content, "Hello ")
        XCTAssertEqual(viewModel.messages[1].role, .system)

        connection.emitPendingApproval(approval)
        await Task.yield()
        XCTAssertEqual(viewModel.pendingApproval?.approvalID, "approval-1")
        XCTAssertEqual(viewModel.connectionState, .showingApproval)

        await viewModel.respondToApproval(true)

        XCTAssertEqual(connection.respondedApprovals.count, 1)
        XCTAssertEqual(connection.respondedApprovals.first?.approvalID, "approval-1")
        XCTAssertEqual(connection.respondedApprovals.first?.approved, true)
    }
}

final class SessionViewModelTests: XCTestCase {
    @MainActor
    func testSessionViewModelDoesNotCreateRemoteSessionWhileConnecting() async {
        let connection = StubConnectionManager()
        connection.state = .connecting
        let viewModel = SessionViewModel(connectionManager: connection, sessions: [])

        viewModel.createSession(named: "Daily")
        await Task.yield()

        XCTAssertTrue(connection.createdSessions.isEmpty)
        XCTAssertTrue(viewModel.sessions.isEmpty)
    }

    @MainActor
    func testSessionViewModelCreatesRemoteSessionWhenConnected() async {
        let connection = StubConnectionManager()
        connection.state = .connected
        let viewModel = SessionViewModel(connectionManager: connection, sessions: [])

        viewModel.createSession(named: "Daily")
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(connection.createdSessions.map(\.name), ["Daily"])
    }

    @MainActor
    func testSessionViewModelAcceptsAuthoritativeSessionUpdatesAndPreservesSelection() async {
        let connection = StubConnectionManager()
        let viewModel = SessionViewModel(connectionManager: connection, sessions: [])

        connection.emitSessions([
            SessionModel(
                id: "session-1",
                name: "Main",
                status: .running,
                createdAtMs: 1,
                lastActiveMs: 2,
                workingDirectory: "/tmp/main"
            ),
            SessionModel(
                id: "session-2",
                name: "Docs",
                status: .idle,
                createdAtMs: 3,
                lastActiveMs: 4,
                workingDirectory: "/tmp/docs"
            ),
        ])
        await Task.yield()

        XCTAssertEqual(viewModel.sessions.map { $0.id }, ["session-1", "session-2"])
        XCTAssertEqual(viewModel.activeSessionID, "session-1")

        viewModel.selectSession(id: "session-2")

        connection.emitSessions([
            SessionModel(
                id: "session-2",
                name: "Docs",
                status: .running,
                createdAtMs: 3,
                lastActiveMs: 5,
                workingDirectory: "/tmp/docs"
            ),
        ])
        await Task.yield()

        XCTAssertEqual(viewModel.sessions.map { $0.id }, ["session-2"])
        XCTAssertEqual(viewModel.activeSessionID, "session-2")
    }
}
