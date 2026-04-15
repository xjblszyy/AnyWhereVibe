import Foundation

final class MessageDispatcher {
    private(set) var messages: [ChatMessage] = []
    private(set) var sessions: [SessionModel] = []
    private(set) var pendingApproval: Mrt_ApprovalRequest?
    private(set) var state: ConnectionState = .disconnected
    private(set) var agentInfo: Mrt_AgentInfo?

    func apply(_ envelope: Mrt_Envelope) {
        guard case .event(let event)? = envelope.payload else {
            return
        }

        switch event.evt {
        case .codexOutput(let output):
            applyCodexOutput(output)
        case .approvalRequest(let approval):
            pendingApproval = approval
            state = .showingApproval
        case .statusUpdate(let update):
            applyStatus(update.status)
        case .sessionList(let update):
            sessions = update.sessions.map(SessionModel.init)
            if let pendingApproval,
               sessions.contains(where: { $0.id == pendingApproval.sessionID }) == false {
                clearPendingApproval()
            }
        case .agentInfo(let info):
            agentInfo = info
            state = .connected
        case .error(let error):
            messages.append(
                ChatMessage(
                    sessionID: nil,
                    content: error.message,
                    isComplete: true,
                    role: .system
                )
            )
            if error.fatal {
                state = .reconnecting
            } else if state != .disconnected {
                state = .connected
            }
        case .none:
            break
        }
    }

    func clearPendingApproval() {
        pendingApproval = nil
        if state == .showingApproval {
            state = .connected
        }
    }

    private func applyCodexOutput(_ output: Mrt_CodexOutput) {
        if let lastIndex = messages.indices.last,
           messages[lastIndex].sessionID == output.sessionID,
           messages[lastIndex].role == .assistant,
           !messages[lastIndex].isComplete {
            messages[lastIndex].content += output.content
            messages[lastIndex].isComplete = output.isComplete
            return
        }

        messages.append(
            ChatMessage(
                sessionID: output.sessionID,
                content: output.content,
                isComplete: output.isComplete,
                role: .assistant
            )
        )
    }

    private func applyStatus(_ status: Mrt_TaskStatus) {
        switch status {
        case .running:
            state = .loading
        case .waitingApproval:
            state = .showingApproval
        case .completed, .idle, .cancelled, .error:
            state = .connected
        case .unspecified, .UNRECOGNIZED:
            break
        }
    }
}
