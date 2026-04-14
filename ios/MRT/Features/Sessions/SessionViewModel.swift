import Foundation
import SwiftUI

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var sessions: [SessionModel]
    @Published var activeSessionID: String?

    init(sessions: [SessionModel]? = nil) {
        let initialSessions = sessions ?? Self.defaultSessions
        self.sessions = initialSessions
        self.activeSessionID = initialSessions.first?.id
    }

    func selectSession(id: String) {
        activeSessionID = id
    }

    func createSession(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let session = SessionModel(
            id: UUID().uuidString,
            name: trimmedName,
            status: .idle,
            createdAtMs: Self.nowMilliseconds(),
            lastActiveMs: Self.nowMilliseconds(),
            workingDirectory: "/tmp/\(trimmedName.replacingOccurrences(of: " ", with: "-").lowercased())"
        )
        sessions.insert(session, at: 0)
        activeSessionID = session.id
    }

    private static var defaultSessions: [SessionModel] {
        [
            SessionModel(
                id: "session-1",
                name: "Main Session",
                status: .running,
                createdAtMs: nowMilliseconds(),
                lastActiveMs: nowMilliseconds(),
                workingDirectory: "/Users/mac/Desktop/AnyWhereVibe"
            ),
            SessionModel(
                id: "session-2",
                name: "Planning",
                status: .idle,
                createdAtMs: nowMilliseconds(),
                lastActiveMs: nowMilliseconds(),
                workingDirectory: "/Users/mac/Desktop"
            ),
        ]
    }

    private static func nowMilliseconds() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1_000)
    }
}
