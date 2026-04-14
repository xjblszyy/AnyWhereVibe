import Foundation
import SwiftUI

struct FeatureChatMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
        case system
    }

    let id: UUID
    let sessionID: String?
    var content: String
    var isComplete: Bool
    let role: Role
    let timestamp: Date

    init(
        id: UUID = UUID(),
        sessionID: String?,
        content: String,
        isComplete: Bool,
        role: Role,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.content = content
        self.isComplete = isComplete
        self.role = role
        self.timestamp = timestamp
    }

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [FeatureChatMessage] = []
    @Published var inputText = ""
    @Published var connectionState: ConnectionState
    @Published var pendingApproval: Mrt_ApprovalRequest? {
        didSet {
            if pendingApproval != nil {
                connectionState = .showingApproval
            } else if connectionState == .showingApproval {
                connectionState = .connected
            }
        }
    }
    @Published var activeSessionID: String? = "session-1"

    private let connectionManager: ConnectionManaging

    init(connectionManager: ConnectionManaging) {
        self.connectionManager = connectionManager
        self.connectionState = connectionManager.state
    }

    var isLoading: Bool {
        get { connectionState == .loading }
        set {
            if newValue {
                connectionState = .loading
            } else if connectionState == .loading {
                connectionState = .connected
            }
        }
    }

    func sendPrompt() async {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        messages.append(
            FeatureChatMessage(
                sessionID: activeSessionID,
                content: prompt,
                isComplete: true,
                role: .user
            )
        )
        inputText = ""
        connectionState = .loading

        do {
            try await connectionManager.sendPrompt(prompt, sessionID: activeSessionID ?? "session-1")
        } catch {
            messages.append(
                FeatureChatMessage(
                    sessionID: activeSessionID,
                    content: "Unable to send prompt right now.",
                    isComplete: true,
                    role: .system
                )
            )
            connectionState = .connected
        }
    }

    func respondToApproval(_ approved: Bool) {
        pendingApproval = nil
        messages.append(
            FeatureChatMessage(
                sessionID: activeSessionID,
                content: approved ? "Approval queued." : "Approval rejected.",
                isComplete: true,
                role: .system
            )
        )
    }
}
