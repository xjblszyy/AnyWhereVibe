import Foundation

struct SessionModel: Identifiable, Equatable {
    let id: String
    let name: String
    let status: Mrt_TaskStatus
    let createdAtMs: UInt64
    let lastActiveMs: UInt64
    let workingDirectory: String

    init(
        id: String,
        name: String,
        status: Mrt_TaskStatus,
        createdAtMs: UInt64,
        lastActiveMs: UInt64,
        workingDirectory: String
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.createdAtMs = createdAtMs
        self.lastActiveMs = lastActiveMs
        self.workingDirectory = workingDirectory
    }

    init(_ session: Mrt_SessionInfo) {
        self.init(
            id: session.sessionID,
            name: session.name,
            status: session.status,
            createdAtMs: session.createdAtMs,
            lastActiveMs: session.lastActiveMs,
            workingDirectory: session.workingDir
        )
    }
}
