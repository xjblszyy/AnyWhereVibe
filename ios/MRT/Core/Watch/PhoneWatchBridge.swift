import Foundation
import WatchConnectivity

protocol WatchSessionControlling: AnyObject {
    var delegate: WCSessionDelegate? { get set }
    var isReachable: Bool { get }

    func activate()
    func updateApplicationContext(_ applicationContext: [String: Any]) throws
    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((any Error) -> Void)?
    )
}

extension WCSession: WatchSessionControlling {}

final class PhoneWatchBridge: NSObject, ObservableObject, WCSessionDelegate {
    enum WatchTaskStatus: Int, Codable, Equatable {
        case idle = 0
        case running = 1
        case waitingApproval = 2
        case completed = 3
        case failed = 4
        case cancelled = 5
    }

    enum QuickAction: String, Equatable {
        case cancel
        case retry
        case `continue`
    }

    struct Snapshot {
        let connectionState: ConnectionState
        let sessions: [SessionModel]
        let activeSessionID: String?
        let lastSummary: String?
        let pendingApproval: Mrt_ApprovalRequest?
    }

    struct SessionSummaryPayload: Codable, Equatable {
        let id: String
        let name: String
        let status: WatchTaskStatus
        let lastSummary: String?
    }

    struct ApprovalPayload: Codable, Equatable {
        let id: String
        let title: String
        let description: String
        let command: String
        let sessionID: String?
    }

    struct WatchStatePayload: Codable, Equatable {
        let isConnected: Bool
        let taskStatus: WatchTaskStatus
        let lastSummary: String?
        let activeSession: SessionSummaryPayload?
    }

    private let sessionController: WatchSessionControlling?
    private let approvalResponder: (String, Bool) -> Void
    private let quickActionHandler: (QuickAction, String) -> Bool
    private let sessionSelectionHandler: (String) -> Bool
    private let encoder = JSONEncoder()
    private var lastPublishedApprovalID: String?

    init(
        sessionController: WatchSessionControlling? = PhoneWatchBridge.defaultSessionController(),
        approvalResponder: @escaping (String, Bool) -> Void,
        quickActionHandler: @escaping (QuickAction, String) -> Bool,
        sessionSelectionHandler: @escaping (String) -> Bool
    ) {
        self.sessionController = sessionController
        self.approvalResponder = approvalResponder
        self.quickActionHandler = quickActionHandler
        self.sessionSelectionHandler = sessionSelectionHandler
        super.init()

        self.sessionController?.delegate = self
        self.sessionController?.activate()
    }

    func sync(snapshot: Snapshot) {
        guard let sessionController else {
            return
        }

        do {
            try sessionController.updateApplicationContext(makeApplicationContext(snapshot: snapshot))
        } catch {
        }

        publishInteractiveEventsIfNeeded(snapshot: snapshot)
    }

    func makeApplicationContext(snapshot: Snapshot) throws -> [String: Any] {
        let sessionPayloads = makeSessionPayloads(snapshot: snapshot)
        let statePayload = WatchStatePayload(
            isConnected: isConnected(snapshot.connectionState),
            taskStatus: status(for: snapshot),
            lastSummary: snapshot.lastSummary,
            activeSession: sessionPayloads.first(where: { $0.id == snapshot.activeSessionID })
        )

        var context: [String: Any] = [
            "watchState": try encoder.encode(statePayload),
            "sessions": try encoder.encode(sessionPayloads),
        ]

        if let pendingApproval = snapshot.pendingApproval {
            context["pendingApproval"] = try encoder.encode(ApprovalPayload(pendingApproval))
        }

        return context
    }

    @discardableResult
    func handleWatchMessage(_ message: [String: Any]) -> Bool {
        guard let type = message["type"] as? String else {
            return false
        }

        switch type {
        case "approval_response":
            guard let approvalID = message["approvalId"] as? String,
                  let approved = message["approved"] as? Bool else {
                return false
            }

            approvalResponder(approvalID, approved)
            return true

        case "quick_action":
            guard let actionRaw = message["action"] as? String,
                  let action = QuickAction(rawValue: actionRaw),
                  let sessionID = message["sessionId"] as? String else {
                return false
            }

            return quickActionHandler(action, sessionID)

        case "select_session":
            guard let sessionID = message["sessionId"] as? String else {
                return false
            }

            return sessionSelectionHandler(sessionID)

        default:
            return false
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
    }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let handled = handleWatchMessage(message)
        replyHandler(["received": true, "handled": handled])
    }

    private func publishInteractiveEventsIfNeeded(snapshot: Snapshot) {
        guard let sessionController, sessionController.isReachable else {
            return
        }

        let approvalID = snapshot.pendingApproval?.approvalID
        defer {
            lastPublishedApprovalID = approvalID
        }

        switch (lastPublishedApprovalID, snapshot.pendingApproval) {
        case let (oldID?, nil) where !oldID.isEmpty:
            sessionController.sendMessage(["type": "approval_cleared"], replyHandler: nil, errorHandler: nil)
        case let (_, approval?):
            sessionController.sendMessage(
                [
                    "type": "approval_request",
                    "approvalId": approval.approvalID,
                    "sessionId": approval.sessionID,
                    "title": "Permission",
                    "description": approval.description_p,
                    "command": approval.command,
                ],
                replyHandler: nil,
                errorHandler: nil
            )
        case (nil, nil):
            break
        default:
            break
        }
    }

    private func makeSessionPayloads(snapshot: Snapshot) -> [SessionSummaryPayload] {
        snapshot.sessions.map { session in
            SessionSummaryPayload(
                id: session.id,
                name: session.name,
                status: mapStatus(session.status),
                lastSummary: session.id == snapshot.activeSessionID ? snapshot.lastSummary : nil
            )
        }
    }

    private func status(for snapshot: Snapshot) -> WatchTaskStatus {
        if snapshot.pendingApproval != nil {
            return .waitingApproval
        }

        if let activeSession = snapshot.sessions.first(where: { $0.id == snapshot.activeSessionID }) {
            return mapStatus(activeSession.status)
        }

        switch snapshot.connectionState {
        case .loading:
            return .running
        case .showingApproval:
            return .waitingApproval
        case .connected, .connecting, .disconnected, .reconnecting:
            return .idle
        }
    }

    private func mapStatus(_ status: Mrt_TaskStatus) -> WatchTaskStatus {
        switch status {
        case .running:
            return .running
        case .waitingApproval:
            return .waitingApproval
        case .completed:
            return .completed
        case .error:
            return .failed
        case .cancelled:
            return .cancelled
        case .idle, .unspecified, .UNRECOGNIZED:
            return .idle
        }
    }

    private func isConnected(_ state: ConnectionState) -> Bool {
        switch state {
        case .connected, .loading, .showingApproval:
            return true
        case .disconnected, .connecting, .reconnecting:
            return false
        }
    }

    private static func defaultSessionController() -> WatchSessionControlling? {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              WCSession.isSupported() else {
            return nil
        }

        return WCSession.default
    }
}

private extension PhoneWatchBridge.ApprovalPayload {
    init(_ request: Mrt_ApprovalRequest) {
        self.init(
            id: request.approvalID,
            title: "Permission",
            description: request.description_p,
            command: request.command,
            sessionID: request.sessionID.isEmpty ? nil : request.sessionID
        )
    }
}
