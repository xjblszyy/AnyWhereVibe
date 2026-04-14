@testable import MRT
import XCTest

final class MessageDispatcherTests: XCTestCase {
    func testDispatcherAppendsStreamingCodexOutputIntoSingleMessage() throws {
        let dispatcher = MessageDispatcher()
        let first = makeCodexOutput(content: "Hello ", complete: false)
        let second = makeCodexOutput(content: "world", complete: true)

        dispatcher.apply(first)
        dispatcher.apply(second)

        XCTAssertEqual(dispatcher.messages.last?.content, "Hello world")
        XCTAssertEqual(dispatcher.messages.last?.isComplete, true)
    }

    func testDispatcherStoresApprovalAndUpdatesState() {
        let dispatcher = MessageDispatcher()

        dispatcher.apply(makeApprovalRequestEnvelope())

        XCTAssertEqual(dispatcher.pendingApproval?.approvalID, "approval-1")
        XCTAssertEqual(dispatcher.state, .showingApproval)
    }

    func testDispatcherUpdatesSessionsFromSessionListEvent() {
        let dispatcher = MessageDispatcher()

        dispatcher.apply(makeSessionListEnvelope())

        XCTAssertEqual(dispatcher.sessions.map(\.id), ["session-1"])
        XCTAssertEqual(dispatcher.sessions.first?.name, "Main")
    }

    func testDispatcherTurnsBusinessErrorsIntoSystemMessages() {
        let dispatcher = MessageDispatcher()

        dispatcher.apply(makeErrorEnvelope(message: "Agent is busy", fatal: false))

        XCTAssertEqual(dispatcher.messages.last?.content, "Agent is busy")
        XCTAssertEqual(dispatcher.messages.last?.role, .system)
        XCTAssertEqual(dispatcher.state, .disconnected)
    }
}

final class PreferencesTests: XCTestCase {
    func testPreferencesStoreDirectHostPortAndConnectionMode() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = Preferences(userDefaults: defaults)

        preferences.directHost = "10.0.0.8"
        preferences.directPort = 9876
        preferences.connectionMode = .direct

        XCTAssertEqual(preferences.directHost, "10.0.0.8")
        XCTAssertEqual(preferences.directPort, 9876)
        XCTAssertEqual(preferences.connectionMode, .direct)
    }
}
