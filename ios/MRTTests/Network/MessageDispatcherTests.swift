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

    func testDispatcherClearsLoadingStateAfterNonFatalError() {
        let dispatcher = MessageDispatcher()

        var runningEnvelope = Mrt_Envelope()
        runningEnvelope.event = .with { event in
            event.statusUpdate = .with { update in
                update.sessionID = "session-1"
                update.status = .running
            }
        }

        dispatcher.apply(runningEnvelope)
        XCTAssertEqual(dispatcher.state, .loading)

        dispatcher.apply(makeErrorEnvelope(message: "Busy", fatal: false))

        XCTAssertEqual(dispatcher.state, .connected)
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

    func testPreferencesStoreManagedFieldsAndSignature() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = Preferences(userDefaults: defaults)

        preferences.connectionMode = .managed
        preferences.nodeURL = "wss://relay.example.com/ws"
        preferences.authToken = "mrt_ak_example1234567890"
        preferences.managedTargetDeviceID = "agent-1"
        preferences.managedTargetDeviceName = "Office Mac"

        XCTAssertEqual(preferences.nodeURL, "wss://relay.example.com/ws")
        XCTAssertEqual(preferences.authToken, "mrt_ak_example1234567890")
        XCTAssertEqual(preferences.managedTargetDeviceID, "agent-1")
        XCTAssertEqual(preferences.managedTargetDeviceName, "Office Mac")
        XCTAssertEqual(
            preferences.connectionConfigurationSignature,
            "managed|127.0.0.1|9876|wss://relay.example.com/ws|mrt_ak_example1234567890|agent-1|Office Mac"
        )
    }
}

final class SettingsValidationTests: XCTestCase {
    func testManagedModeRequiresNodeURL() {
        XCTAssertEqual(
            settingsValidationMessage(
                mode: .managed,
                host: "127.0.0.1",
                portText: "9876",
                nodeURL: "",
                authToken: "mrt_ak_example1234567890"
            ),
            "Connection Node URL is required for managed mode."
        )
    }

    func testManagedModeRequiresAuthToken() {
        XCTAssertEqual(
            settingsValidationMessage(
                mode: .managed,
                host: "127.0.0.1",
                portText: "9876",
                nodeURL: "wss://relay.example.com/ws",
                authToken: ""
            ),
            "Auth token is required for managed mode."
        )
    }
}
