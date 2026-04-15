import SwiftUI

enum TaskDisplayStatus: Int, Codable, CaseIterable, Hashable {
    case idle = 0
    case running = 1
    case waitingApproval = 2
    case completed = 3
    case failed = 4
    case cancelled = 5

    var displayText: String {
        switch self {
        case .idle:
            return "Idle"
        case .running:
            return "Running"
        case .waitingApproval:
            return "Needs approval"
        case .completed:
            return "Complete"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    var iconName: String {
        switch self {
        case .idle:
            return "pause.circle.fill"
        case .running:
            return "hammer.circle.fill"
        case .waitingApproval:
            return "questionmark.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .cancelled:
            return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle:
            return WatchGH.textTertiary
        case .running:
            return WatchGH.accentBlue
        case .waitingApproval:
            return WatchGH.accentYellow
        case .completed:
            return WatchGH.accentGreen
        case .failed:
            return WatchGH.accentRed
        case .cancelled:
            return WatchGH.accentOrange
        }
    }
}

struct SessionSummary: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    var status: TaskDisplayStatus
    var lastSummary: String?
}

struct ApprovalInfo: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let description: String
    let command: String
    let sessionId: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case command
        case sessionId
        case sessionID
    }

    init(
        id: String,
        title: String,
        description: String,
        command: String = "",
        sessionId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.command = command
        self.sessionId = sessionId
    }

    init?(from message: [String: Any]) {
        guard let id = message["approvalId"] as? String ?? message["id"] as? String else {
            return nil
        }

        self.init(
            id: id,
            title: message["title"] as? String ?? "Permission",
            description: message["description"] as? String ?? message["message"] as? String ?? "Codex needs approval.",
            command: message["command"] as? String ?? "",
            sessionId: message["sessionId"] as? String
        )
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        command = try container.decode(String.self, forKey: .command)
        if let decodedSessionId = try container.decodeIfPresent(String.self, forKey: .sessionId) {
            sessionId = decodedSessionId
        } else {
            sessionId = try container.decodeIfPresent(String.self, forKey: .sessionID)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(command, forKey: .command)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
    }
}

struct WatchState: Codable, Hashable {
    var isConnected: Bool
    var taskStatus: TaskDisplayStatus
    var lastSummary: String?
    var activeSession: SessionSummary?

    static let disconnected = WatchState(
        isConnected: false,
        taskStatus: .idle,
        lastSummary: nil,
        activeSession: nil
    )
}
