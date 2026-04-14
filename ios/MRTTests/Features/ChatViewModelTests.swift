@testable import MRT
import XCTest

final class ChatViewModelTests: XCTestCase {
    @MainActor
    func testSendPromptCreatesUserMessageAndStartsLoading() async {
        let connection = StubConnectionManager()
        let viewModel = ChatViewModel(connectionManager: connection)

        viewModel.inputText = "Ship it"
        await viewModel.sendPrompt()

        XCTAssertEqual(viewModel.messages.first?.role, .user)
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertEqual(connection.sentPrompts.map(\.prompt), ["Ship it"])
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
