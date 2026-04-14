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
    @Published var activeSessionID: String? = "session-1" {
        didSet {
            rebuildMessages()
        }
    }

    private let connectionManager: ConnectionManaging
    private var localMessages: [FeatureChatMessage] = []
    private var remoteMessages: [ChatMessage] = []
    private var hasAttemptedInitialConnect = false

    init(connectionManager: ConnectionManaging) {
        self.connectionManager = connectionManager
        self.connectionState = connectionManager.state
        self.remoteMessages = connectionManager.messages
        self.pendingApproval = connectionManager.pendingApproval
        bindConnectionManager()
        rebuildMessages()
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

        let userMessage = FeatureChatMessage(
            sessionID: activeSessionID,
            content: prompt,
            isComplete: true,
            role: .user
        )
        localMessages.append(userMessage)
        rebuildMessages()

        inputText = ""
        connectionState = .loading

        do {
            try await connectionManager.sendPrompt(prompt, sessionID: activeSessionID ?? "session-1")
        } catch {
            localMessages.append(
                FeatureChatMessage(
                    sessionID: activeSessionID,
                    content: "Unable to send prompt right now.",
                    isComplete: true,
                    role: .system
                )
            )
            rebuildMessages()
            connectionState = connectionManager.state
        }
    }

    func respondToApproval(_ approved: Bool) async {
        guard let approvalID = pendingApproval?.approvalID else { return }

        do {
            try await connectionManager.respondToApproval(approvalID, approved: approved)
            pendingApproval = nil
        } catch {
        }
    }

    var lastMessageSignature: String {
        guard let lastMessage = messages.last else { return "empty" }
        return "\(lastMessage.id.uuidString):\(lastMessage.content.count):\(lastMessage.isComplete)"
    }

    func connectIfNeeded(host: String, port: Int, mode: ConnectionMode) async {
        guard mode == .direct else { return }
        guard !hasAttemptedInitialConnect else { return }
        hasAttemptedInitialConnect = true

        do {
            try await connectionManager.connect(host: host, port: port)
        } catch {
            connectionState = .disconnected
        }
    }

    private func bindConnectionManager() {
        connectionManager.onStateChange = { [weak self] newState in
            Task { @MainActor in
                self?.connectionState = newState
            }
        }
        connectionManager.onMessagesChange = { [weak self] newMessages in
            Task { @MainActor in
                self?.remoteMessages = newMessages
                self?.rebuildMessages()
            }
        }
        connectionManager.onPendingApprovalChange = { [weak self] approval in
            Task { @MainActor in
                self?.pendingApproval = approval
            }
        }
    }

    private func rebuildMessages() {
        let mappedRemote = remoteMessages.map { message in
            FeatureChatMessage(
                id: message.id,
                sessionID: message.sessionID,
                content: message.content,
                isComplete: message.isComplete,
                role: mapRole(message.role),
                timestamp: Date()
            )
        }
        messages = (localMessages + mappedRemote).filter(isVisibleInActiveThread)
    }

    private func mapRole(_ role: ChatMessage.Role) -> FeatureChatMessage.Role {
        switch role {
        case .assistant:
            return .assistant
        case .system:
            return .system
        }
    }

    private func isVisibleInActiveThread(_ message: FeatureChatMessage) -> Bool {
        if message.sessionID == activeSessionID {
            return true
        }

        return message.sessionID == nil && message.role == .system
    }
}
