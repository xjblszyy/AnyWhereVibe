import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role: String, Equatable {
        case assistant
        case system
    }

    let id: UUID
    let sessionID: String?
    var content: String
    var isComplete: Bool
    let role: Role

    init(
        id: UUID = UUID(),
        sessionID: String?,
        content: String,
        isComplete: Bool,
        role: Role
    ) {
        self.id = id
        self.sessionID = sessionID
        self.content = content
        self.isComplete = isComplete
        self.role = role
    }
}
