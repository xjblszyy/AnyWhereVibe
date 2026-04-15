import Foundation
import SwiftUI

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var sessions: [SessionModel]
    @Published var activeSessionID: String?

    private let connectionManager: ConnectionManaging?

    init(connectionManager: ConnectionManaging? = nil, sessions: [SessionModel]? = nil) {
        self.connectionManager = connectionManager
        let initialSessions = sessions ?? (connectionManager == nil ? Self.defaultSessions : connectionManager?.sessions ?? [])
        self.sessions = initialSessions
        self.activeSessionID = initialSessions.first?.id
        connectionManager?.onSessionsChange = { [weak self] authoritativeSessions in
            Task { @MainActor in
                self?.applyAuthoritativeSessions(authoritativeSessions)
            }
        }
    }

    @discardableResult
    func selectSession(id: String) -> Bool {
        guard sessions.contains(where: { $0.id == id }) else {
            return false
        }

        activeSessionID = id

        guard let connectionManager else {
            return true
        }

        Task {
            try? await connectionManager.switchSession(to: id)
        }

        return true
    }

    func canCreateSession(connectionState: ConnectionState? = nil) -> Bool {
        guard connectionManager != nil else { return true }
        return (connectionState ?? connectionManager?.state) == .connected
    }

    func createSession(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let connectionManager {
            guard canCreateSession() else { return }
            Task {
                try? await connectionManager.createSession(name: trimmedName, workingDirectory: "")
            }
            return
        }

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

    func closeSession(id: String) {
        if let connectionManager {
            guard sessions.contains(where: { $0.id == id }) else { return }
            Task {
                try? await connectionManager.closeSession(id: id)
            }
            return
        }

        sessions.removeAll { $0.id == id }
        if activeSessionID == id {
            activeSessionID = sessions.first?.id
        }
    }

    func cancelTask(id: String) {
        if let connectionManager {
            guard sessions.contains(where: { $0.id == id }) else { return }
            Task {
                try? await connectionManager.cancelTask(sessionID: id)
            }
            return
        }

        let updatedAt = Self.nowMilliseconds()
        sessions = sessions.map { session in
            guard session.id == id else { return session }
            return SessionModel(
                id: session.id,
                name: session.name,
                status: .cancelled,
                createdAtMs: session.createdAtMs,
                lastActiveMs: updatedAt,
                workingDirectory: session.workingDirectory
            )
        }
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

    private func applyAuthoritativeSessions(_ authoritativeSessions: [SessionModel]) {
        let previousActiveSessionID = activeSessionID
        sessions = authoritativeSessions

        if let previousActiveSessionID,
           authoritativeSessions.contains(where: { $0.id == previousActiveSessionID }) {
            activeSessionID = previousActiveSessionID
        } else {
            activeSessionID = authoritativeSessions.first?.id
        }
    }
}
