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
        case .uiSmokeFiles:
            ContentView(
                connectionManager: UITestConnectionManager(filesSmokeEnabled: true),
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
    case uiSmokeFiles

    init(arguments: [String]) {
        if arguments.contains("MRT_UI_SMOKE_GIT") {
            self = .uiSmokeGit
        } else if arguments.contains("MRT_UI_SMOKE_FILES") {
            self = .uiSmokeFiles
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

    var onFileResult: ((Mrt_Envelope) -> Void)?
    var onGitResult: ((Mrt_Envelope) -> Void)?

    var onSessionsChange: (([SessionModel]) -> Void)? {
        didSet { onSessionsChange?(sessions) }
    }

    private let gitSmokeEnabled: Bool
    private let filesSmokeEnabled: Bool
    private var fileEntries: [String: [UITestFileEntry]]
    private var fileContents: [String: String]

    init(gitSmokeEnabled: Bool = false, filesSmokeEnabled: Bool = false) {
        self.gitSmokeEnabled = gitSmokeEnabled
        self.filesSmokeEnabled = filesSmokeEnabled
        self.pendingApproval = nil
        self.sessions = Self.demoSessions
        self.fileEntries = Self.defaultFileEntries
        self.fileContents = Self.defaultFileContents
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

    func listDirectory(sessionID: String, path: String) async throws -> String {
        let requestID = UUID().uuidString
        guard filesSmokeEnabled else { return requestID }
        let entries = fileEntries[path] ?? []
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var envelope = Mrt_Envelope()
            envelope.requestID = requestID
            envelope.fileResult = .with { result in
                result.sessionID = sessionID
                result.dirListing = .with { listing in
                    listing.entries = entries.map { entry in
                        .with { proto in
                            proto.name = entry.name
                            proto.path = entry.path
                            proto.isDir = entry.isDirectory
                            proto.size = entry.size
                            proto.modifiedMs = entry.modifiedMs
                        }
                    }
                }
            }
            self.onFileResult?(envelope)
        }
        return requestID
    }

    func readFile(sessionID: String, path: String) async throws -> String {
        let requestID = UUID().uuidString
        guard filesSmokeEnabled else { return requestID }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var envelope = Mrt_Envelope()
            envelope.requestID = requestID
            if let content = self.fileContents[path] {
                envelope.fileResult = .with { result in
                    result.sessionID = sessionID
                    result.fileContent = .with { file in
                        file.path = path
                        file.content = Data(content.utf8)
                        file.mimeType = "text/plain"
                    }
                }
            } else {
                envelope.fileResult = .with { result in
                    result.sessionID = sessionID
                    result.error = .with { error in
                        error.code = "FILE_NOT_FOUND"
                        error.message = "Missing file"
                        error.fatal = false
                    }
                }
            }
            self.onFileResult?(envelope)
        }
        return requestID
    }

    func writeFile(sessionID: String, path: String, content: Data) async throws -> String {
        let requestID = UUID().uuidString
        guard filesSmokeEnabled else { return requestID }
        fileContents[path] = String(decoding: content, as: UTF8.self)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var envelope = Mrt_Envelope()
            envelope.requestID = requestID
            envelope.fileResult = .with { result in
                result.sessionID = sessionID
                result.writeAck = .with { ack in
                    ack.path = path
                    ack.success = true
                }
            }
            self.onFileResult?(envelope)
        }
        return requestID
    }

    func createFile(sessionID: String, path: String) async throws -> String {
        let requestID = UUID().uuidString
        guard filesSmokeEnabled else { return requestID }
        fileContents[path] = ""
        addEntry(path: path, isDirectory: false)
        DispatchQueue.main.async { [weak self] in
            self?.emitMutationAck(sessionID: sessionID, requestID: requestID, path: path, message: "created")
        }
        return requestID
    }

    func createDirectory(sessionID: String, path: String) async throws -> String {
        let requestID = UUID().uuidString
        guard filesSmokeEnabled else { return requestID }
        fileEntries[path] = []
        addEntry(path: path, isDirectory: true)
        DispatchQueue.main.async { [weak self] in
            self?.emitMutationAck(sessionID: sessionID, requestID: requestID, path: path, message: "created")
        }
        return requestID
    }

    func deletePath(sessionID: String, path: String, recursive: Bool) async throws -> String {
        let requestID = UUID().uuidString
        guard filesSmokeEnabled else { return requestID }
        fileContents.removeValue(forKey: path)
        fileEntries.removeValue(forKey: path)
        removeEntry(path: path)
        DispatchQueue.main.async { [weak self] in
            self?.emitMutationAck(sessionID: sessionID, requestID: requestID, path: path, message: "deleted")
        }
        return requestID
    }

    func renamePath(sessionID: String, fromPath: String, toPath: String) async throws -> String {
        let requestID = UUID().uuidString
        guard filesSmokeEnabled else { return requestID }
        if let content = fileContents.removeValue(forKey: fromPath) {
            fileContents[toPath] = content
        }
        if let entries = fileEntries.removeValue(forKey: fromPath) {
            fileEntries[toPath] = entries
        }
        removeEntry(path: fromPath)
        addEntry(path: toPath, isDirectory: fileEntries[toPath] != nil)
        DispatchQueue.main.async { [weak self] in
            self?.emitMutationAck(sessionID: sessionID, requestID: requestID, path: toPath, message: "renamed")
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

    private func emitMutationAck(sessionID: String, requestID: String, path: String, message: String) {
        var envelope = Mrt_Envelope()
        envelope.requestID = requestID
        envelope.fileResult = .with { result in
            result.sessionID = sessionID
            result.mutationAck = .with { ack in
                ack.path = path
                ack.success = true
                ack.message = message
            }
        }
        onFileResult?(envelope)
    }

    private func addEntry(path: String, isDirectory: Bool) {
        let parent = path.split(separator: "/").dropLast().joined(separator: "/")
        let name = path.split(separator: "/").last.map(String.init) ?? path
        var entries = fileEntries[parent] ?? []
        if entries.contains(where: { $0.path == path }) == false {
            entries.append(UITestFileEntry(name: name, path: path, isDirectory: isDirectory))
            entries.sort { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
                return lhs.name < rhs.name
            }
            fileEntries[parent] = entries
        }
        if isDirectory, fileEntries[path] == nil {
            fileEntries[path] = []
        }
    }

    private func removeEntry(path: String) {
        let parent = path.split(separator: "/").dropLast().joined(separator: "/")
        fileEntries[parent] = (fileEntries[parent] ?? []).filter { $0.path != path }
    }

    private static var defaultFileEntries: [String: [UITestFileEntry]] {
        [
            "": [
                UITestFileEntry(name: "Sources", path: "Sources", isDirectory: true),
                UITestFileEntry(name: "notes.txt", path: "notes.txt", isDirectory: false),
            ],
            "Sources": [
                UITestFileEntry(name: "App.swift", path: "Sources/App.swift", isDirectory: false),
            ],
        ]
    }

    private static var defaultFileContents: [String: String] {
        [
            "notes.txt": "Remember to ship the files slice.\n",
            "Sources/App.swift": "let enabled = false\n",
        ]
    }
}

private struct UITestFileEntry {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: UInt64
    let modifiedMs: UInt64

    init(name: String, path: String, isDirectory: Bool) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = isDirectory ? 0 : 128
        self.modifiedMs = UInt64(Date().timeIntervalSince1970 * 1_000)
    }
}
