import Foundation
import WatchConnectivity

final class WatchBridge: NSObject, ObservableObject, WCSessionDelegate {
    @Published var currentState: WatchState = .disconnected
    @Published var pendingApproval: ApprovalInfo?
    @Published var sessions: [SessionSummary] = []

    override init() {
        super.init()

        guard WCSession.isSupported() else {
            return
        }

        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func sendApprovalResponse(approvalId: String, approved: Bool) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.isReachable else { return }

        session.sendMessage(
            ["type": "approval_response", "approvalId": approvalId, "approved": approved],
            replyHandler: nil,
            errorHandler: nil
        )

        DispatchQueue.main.async {
            self.pendingApproval = nil
        }
    }

    func sendQuickAction(_ action: String, sessionId: String) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.isReachable else { return }

        session.sendMessage(
            ["type": "quick_action", "action": action, "sessionId": sessionId],
            replyHandler: nil,
            errorHandler: nil
        )
    }

    func selectSession(withID sessionID: String) {
        DispatchQueue.main.async {
            guard let session = self.sessions.first(where: { $0.id == sessionID }) else {
                return
            }

            self.currentState.activeSession = session
            self.currentState.taskStatus = session.status
            self.currentState.lastSummary = session.lastSummary
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.currentState.isConnected = error == nil && activationState == .activated
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.currentState.isConnected = session.activationState == .activated && session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            if let data = applicationContext["watchState"] as? Data,
               let state = try? JSONDecoder().decode(WatchState.self, from: data) {
                self.currentState = state
            }

            if let data = applicationContext["sessions"] as? Data,
               let decodedSessions = try? JSONDecoder().decode([SessionSummary].self, from: data) {
                self.replaceSessions(decodedSessions)
            }

            if let data = applicationContext["pendingApproval"] as? Data,
               let approval = try? JSONDecoder().decode(ApprovalInfo.self, from: data) {
                self.pendingApproval = approval
            }
        }
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        DispatchQueue.main.async {
            if let type = message["type"] as? String {
                switch type {
                case "approval_request":
                    self.pendingApproval = ApprovalInfo(from: message)
                case "approval_cleared":
                    self.pendingApproval = nil
                case "status_update":
                    self.applyStatusUpdate(message)
                case "session_list":
                    self.applySessionList(message)
                default:
                    break
                }
            }

            replyHandler(["received": true])
        }
    }

    private func applyStatusUpdate(_ message: [String: Any]) {
        if let statusRaw = message["status"] as? Int {
            currentState.taskStatus = TaskDisplayStatus(rawValue: statusRaw) ?? .idle
        }

        if let summary = message["summary"] as? String {
            currentState.lastSummary = summary
        }

        if let sessionID = message["sessionId"] as? String,
           let sessionName = message["sessionName"] as? String {
            let session = SessionSummary(
                id: sessionID,
                name: sessionName,
                status: currentState.taskStatus,
                lastSummary: currentState.lastSummary
            )
            upsertSession(session)
            currentState.activeSession = session
        }

        currentState.isConnected = true
    }

    private func applySessionList(_ message: [String: Any]) {
        if let data = message["sessions"] as? Data,
           let decodedSessions = try? JSONDecoder().decode([SessionSummary].self, from: data) {
            replaceSessions(decodedSessions)
            return
        }

        guard let rawSessions = message["sessions"] as? [[String: Any]] else {
            return
        }

        let decodedSessions = rawSessions.compactMap { entry -> SessionSummary? in
            guard let id = entry["id"] as? String,
                  let name = entry["name"] as? String else {
                return nil
            }

            let status = TaskDisplayStatus(rawValue: entry["status"] as? Int ?? 0) ?? .idle
            return SessionSummary(
                id: id,
                name: name,
                status: status,
                lastSummary: entry["lastSummary"] as? String
            )
        }

        replaceSessions(decodedSessions)
    }

    private func replaceSessions(_ newSessions: [SessionSummary]) {
        sessions = newSessions

        if let activeSessionID = currentState.activeSession?.id,
           let matchingSession = newSessions.first(where: { $0.id == activeSessionID }) {
            currentState.activeSession = matchingSession
            currentState.taskStatus = matchingSession.status
            currentState.lastSummary = matchingSession.lastSummary
            return
        }

        currentState.activeSession = newSessions.first
        currentState.taskStatus = newSessions.first?.status ?? currentState.taskStatus
        currentState.lastSummary = newSessions.first?.lastSummary ?? currentState.lastSummary
    }

    private func upsertSession(_ session: SessionSummary) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
    }
}
