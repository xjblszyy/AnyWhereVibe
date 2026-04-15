import SwiftUI

@main
struct MRTApp: App {
    private let launchMode = AppLaunchMode(arguments: ProcessInfo.processInfo.arguments)

    var body: some Scene {
        WindowGroup {
            rootView
                .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch launchMode {
        case .standard:
            ContentView()
        case .uiSmoke:
            ContentView(
                connectionManager: UITestConnectionManager(),
                preferences: Preferences(userDefaults: makeUITestUserDefaults())
            )
        case .uiSmokeGit:
            ContentView(
                connectionManager: UITestConnectionManager(gitSmokeEnabled: true),
                preferences: Preferences(userDefaults: makeUITestUserDefaults())
            )
        }
    }

    private func makeUITestUserDefaults() -> UserDefaults {
        let suiteName = "com.anywherevibe.mrt.uitests.defaults"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private enum AppLaunchMode {
    case standard
    case uiSmoke
    case uiSmokeGit

    init(arguments: [String]) {
        if arguments.contains("MRT_UI_SMOKE_GIT") {
            self = .uiSmokeGit
        } else if arguments.contains("MRT_UI_SMOKE") {
            self = .uiSmoke
        } else {
            self = .standard
        }
    }
}

private final class UITestConnectionManager: ConnectionManaging {
    var state: ConnectionState = .connected {
        didSet { onStateChange?(state) }
    }

    var messages: [ChatMessage] = [] {
        didSet { onMessagesChange?(messages) }
    }

    var pendingApproval: Mrt_ApprovalRequest? {
        didSet { onPendingApprovalChange?(pendingApproval) }
    }

    var sessions: [SessionModel] {
        didSet { onSessionsChange?(sessions) }
    }

    var onStateChange: ((ConnectionState) -> Void)? {
        didSet { onStateChange?(state) }
    }

    var onMessagesChange: (([ChatMessage]) -> Void)? {
        didSet { onMessagesChange?(messages) }
    }

    var onPendingApprovalChange: ((Mrt_ApprovalRequest?) -> Void)? {
        didSet { onPendingApprovalChange?(pendingApproval) }
    }

    var onGitResult: ((Mrt_Envelope) -> Void)?

    var onSessionsChange: (([SessionModel]) -> Void)? {
        didSet { onSessionsChange?(sessions) }
    }

    private let gitSmokeEnabled: Bool

    init(gitSmokeEnabled: Bool = false) {
        self.gitSmokeEnabled = gitSmokeEnabled
        self.pendingApproval = nil
        self.sessions = Self.demoSessions
    }

    func connect(host: String, port: Int) async throws {
        state = .connected
    }

    func disconnect() {
        state = .disconnected
    }

    func sendPrompt(_ prompt: String, sessionID: String) async throws {
        messages.append(
            ChatMessage(
                sessionID: sessionID,
                content: "UI smoke reply for: \(prompt)",
                isComplete: true,
                role: .assistant
            )
        )
    }

    func respondToApproval(_ approvalID: String, approved: Bool) async throws {
        pendingApproval = nil
    }

    func cancelTask(sessionID: String) async throws {
        updateSession(id: sessionID, status: .cancelled)
    }

    func switchSession(to sessionID: String) async throws {
    }

    func createSession(name: String, workingDirectory: String) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let timestamp = Self.nowMilliseconds()
        sessions.insert(
            SessionModel(
                id: "session-\(UUID().uuidString.lowercased())",
                name: trimmedName,
                status: .idle,
                createdAtMs: timestamp,
                lastActiveMs: timestamp,
                workingDirectory: workingDirectory.isEmpty ? "/tmp/\(trimmedName.replacingOccurrences(of: " ", with: "-").lowercased())" : workingDirectory
            ),
            at: 0
        )
    }

    func closeSession(id: String) async throws {
        sessions.removeAll { $0.id == id }
    }

    func requestGitStatus(sessionID: String) async throws -> String {
        let requestID = UUID().uuidString
        guard gitSmokeEnabled else {
            return requestID
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var envelope = Mrt_Envelope()
            envelope.requestID = requestID
            envelope.gitResult = .with { result in
                result.sessionID = sessionID
                result.status = .with { status in
                    status.branch = "main"
                    status.tracking = "origin/main"
                    status.isClean = false
                    status.changes = [
                        .with { change in
                            change.path = "Sources/App.swift"
                            change.status = "modified"
                        },
                        .with { change in
                            change.path = "README.md"
                            change.status = "untracked"
                        },
                    ]
                }
            }
            self.onGitResult?(envelope)
        }
        return requestID
    }

    func requestGitDiff(sessionID: String, path: String) async throws -> String {
        let requestID = UUID().uuidString
        guard gitSmokeEnabled else {
            return requestID
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var envelope = Mrt_Envelope()
            envelope.requestID = requestID
            envelope.gitResult = .with { result in
                result.sessionID = sessionID
                result.diff = .with { payload in
                    if path == "Sources/App.swift" {
                        payload.diff = """
                        diff --git a/Sources/App.swift b/Sources/App.swift
                        --- a/Sources/App.swift
                        +++ b/Sources/App.swift
                        @@ -1,1 +1,1 @@
                        -let enabled = false
                        +let enabled = true
                        """
                    } else {
                        payload.diff = """
                        diff --git a/README.md b/README.md
                        --- /dev/null
                        +++ b/README.md
                        @@ -0,0 +1,1 @@
                        +Git smoke fixture
                        """
                    }
                }
            }
            self.onGitResult?(envelope)
        }
        return requestID
    }

    private func updateSession(id: String, status: Mrt_TaskStatus) {
        let updatedAt = Self.nowMilliseconds()
        sessions = sessions.map { session in
            guard session.id == id else { return session }
            return SessionModel(
                id: session.id,
                name: session.name,
                status: status,
                createdAtMs: session.createdAtMs,
                lastActiveMs: updatedAt,
                workingDirectory: session.workingDirectory
            )
        }
    }

    private static var demoSessions: [SessionModel] {
        [
            SessionModel(
                id: "session-main",
                name: "Terminal Ops",
                status: .running,
                createdAtMs: nowMilliseconds(),
                lastActiveMs: nowMilliseconds(),
                workingDirectory: "/Users/mac/Desktop/AnyWhereVibe"
            ),
            SessionModel(
                id: "session-docs",
                name: "Docs Review",
                status: .idle,
                createdAtMs: nowMilliseconds(),
                lastActiveMs: nowMilliseconds(),
                workingDirectory: "/Users/mac/Desktop/AnyWhereVibe/docs"
            ),
        ]
    }

    private static func nowMilliseconds() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1_000)
    }
}
