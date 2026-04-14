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
}
