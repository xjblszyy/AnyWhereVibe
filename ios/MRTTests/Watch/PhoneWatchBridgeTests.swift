@testable import MRT
import XCTest

final class PhoneWatchBridgeTests: XCTestCase {
    func testMakeApplicationContextEncodesMappedWatchSnapshot() throws {
        let bridge = PhoneWatchBridge(
            sessionController: nil,
            approvalResponder: { _, _ in },
            quickActionHandler: { _, _ in false },
            sessionSelectionHandler: { _ in false }
        )

        let context = try bridge.makeApplicationContext(
            snapshot: .init(
                connectionState: .loading,
                sessions: [
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
                        status: .completed,
                        createdAtMs: 3,
                        lastActiveMs: 4,
                        workingDirectory: "/tmp/docs"
                    ),
                ],
                activeSessionID: "session-1",
                lastSummary: "Applying patch",
                pendingApproval: makeApprovalRequest()
            )
        )

        let watchStateData = try XCTUnwrap(context["watchState"] as? Data)
        let sessionsData = try XCTUnwrap(context["sessions"] as? Data)
        let pendingApprovalData = try XCTUnwrap(context["pendingApproval"] as? Data)

        let decoder = JSONDecoder()
        let state = try decoder.decode(PhoneWatchBridge.WatchStatePayload.self, from: watchStateData)
        let sessions = try decoder.decode([PhoneWatchBridge.SessionSummaryPayload].self, from: sessionsData)
        let approval = try decoder.decode(PhoneWatchBridge.ApprovalPayload.self, from: pendingApprovalData)

        XCTAssertTrue(state.isConnected)
        XCTAssertEqual(state.taskStatus, .waitingApproval)
        XCTAssertEqual(state.lastSummary, "Applying patch")
        XCTAssertEqual(state.activeSession?.id, "session-1")
        XCTAssertEqual(state.activeSession?.status, .running)

        XCTAssertEqual(sessions.map(\.id), ["session-1", "session-2"])
        XCTAssertEqual(sessions.map(\.status), [.running, .completed])
        XCTAssertEqual(sessions.first?.lastSummary, "Applying patch")
        XCTAssertNil(sessions.last?.lastSummary)

        XCTAssertEqual(approval.id, "approval-1")
        XCTAssertEqual(approval.sessionID, "session-1")
        XCTAssertEqual(approval.description, "Write to file src/main.rs")
        XCTAssertEqual(approval.command, "echo hi")
    }

    func testHandleWatchMessageRoutesApprovalResponse() {
        var capturedApproval: (String, Bool)?
        let bridge = PhoneWatchBridge(
            sessionController: nil,
            approvalResponder: { approvalID, approved in
                capturedApproval = (approvalID, approved)
            },
            quickActionHandler: { _, _ in false },
            sessionSelectionHandler: { _ in false }
        )

        let handled = bridge.handleWatchMessage([
            "type": "approval_response",
            "approvalId": "approval-42",
            "approved": true,
        ])

        XCTAssertTrue(handled)
        XCTAssertEqual(capturedApproval?.0, "approval-42")
        XCTAssertEqual(capturedApproval?.1, true)
    }

    func testHandleWatchMessageRoutesSupportedCancelQuickAction() {
        var capturedAction: (PhoneWatchBridge.QuickAction, String)?
        let bridge = PhoneWatchBridge(
            sessionController: nil,
            approvalResponder: { _, _ in },
            quickActionHandler: { action, sessionID in
                capturedAction = (action, sessionID)
                return action == .cancel
            },
            sessionSelectionHandler: { _ in false }
        )

        let handled = bridge.handleWatchMessage([
            "type": "quick_action",
            "action": "cancel",
            "sessionId": "session-1",
        ])

        XCTAssertTrue(handled)
        XCTAssertEqual(capturedAction?.0, .cancel)
        XCTAssertEqual(capturedAction?.1, "session-1")
    }

    func testHandleWatchMessageLeavesUnsupportedQuickActionAsNoOp() {
        var capturedAction: PhoneWatchBridge.QuickAction?
        let bridge = PhoneWatchBridge(
            sessionController: nil,
            approvalResponder: { _, _ in },
            quickActionHandler: { action, _ in
                capturedAction = action
                return false
            },
            sessionSelectionHandler: { _ in false }
        )

        let handled = bridge.handleWatchMessage([
            "type": "quick_action",
            "action": "retry",
            "sessionId": "session-1",
        ])

        XCTAssertFalse(handled)
        XCTAssertEqual(capturedAction, .retry)
    }

    func testHandleWatchMessageRoutesSessionSelectionWhenPresent() {
        var selectedSessionID: String?
        let bridge = PhoneWatchBridge(
            sessionController: nil,
            approvalResponder: { _, _ in },
            quickActionHandler: { _, _ in false },
            sessionSelectionHandler: { sessionID in
                selectedSessionID = sessionID
                return true
            }
        )

        let handled = bridge.handleWatchMessage([
            "type": "select_session",
            "sessionId": "session-2",
        ])

        XCTAssertTrue(handled)
        XCTAssertEqual(selectedSessionID, "session-2")
    }
}
