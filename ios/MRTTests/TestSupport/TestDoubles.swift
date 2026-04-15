@testable import MRT
import Foundation
import SwiftProtobuf

final class StubWebSocketClient: WebSocketClientProtocol {
    enum StubError: Error {
        case connectFailed
    }

    var sentData: [Data] = []
    var connectedURL: URL?
    var connectCalls: [URL] = []
    var disconnectCallCount = 0
    var nextConnectDelayNanoseconds: UInt64?
    var connectErrors: [Error] = []
    var receiveCallbackHistory: [(Data) -> Void] = []
    var closeCallbackHistory: [() -> Void] = []
    var onReceive: ((Data) -> Void)? {
        didSet {
            if let onReceive {
                receiveCallbackHistory.append(onReceive)
            }
        }
    }
    var onClose: (() -> Void)? {
        didSet {
            if let onClose {
                closeCallbackHistory.append(onClose)
            }
        }
    }

    func connect(url: URL) async throws {
        connectedURL = url
        connectCalls.append(url)
        if !connectErrors.isEmpty {
            throw connectErrors.removeFirst()
        }
        if let delay = nextConnectDelayNanoseconds {
            nextConnectDelayNanoseconds = nil
            try await Task.sleep(nanoseconds: delay)
        }
    }

    func send(_ data: Data) async throws {
        sentData.append(data)
    }

    func disconnect() {
        disconnectCallCount += 1
        onClose?()
    }

    func pushIncomingEnvelope(_ envelope: Mrt_Envelope) {
        let data = try! ProtobufCodec.encode(envelope)
        onReceive?(data)
    }

    func simulateIncomingData(_ data: Data) {
        onReceive?(data)
    }

    func simulateClose() {
        onClose?()
    }
}

final class StubConnectionManager: ConnectionManaging {
    var state: ConnectionState = .disconnected
    var messages: [ChatMessage] = []
    var pendingApproval: Mrt_ApprovalRequest?
    var sessions: [SessionModel] = []
    var onStateChange: ((ConnectionState) -> Void)?
    var onMessagesChange: (([ChatMessage]) -> Void)?
    var onPendingApprovalChange: ((Mrt_ApprovalRequest?) -> Void)?
    var onSessionsChange: (([SessionModel]) -> Void)?
    var onFileResult: ((Mrt_Envelope) -> Void)?
    var onGitResult: ((Mrt_Envelope) -> Void)?
    var sentPrompts: [(prompt: String, sessionID: String)] = []
    var respondedApprovals: [(approvalID: String, approved: Bool)] = []
    var createdSessions: [(name: String, workingDirectory: String)] = []
    var cancelledSessions: [String] = []
    var closedSessions: [String] = []
    var listedDirectories: [(sessionID: String, path: String, requestID: String)] = []
    var readFiles: [(sessionID: String, path: String, requestID: String)] = []
    var wroteFiles: [(sessionID: String, path: String, content: Data, requestID: String)] = []
    var createdFiles: [(sessionID: String, path: String, requestID: String)] = []
    var createdDirectories: [(sessionID: String, path: String, requestID: String)] = []
    var deletedPaths: [(sessionID: String, path: String, recursive: Bool, requestID: String)] = []
    var renamedPaths: [(sessionID: String, fromPath: String, toPath: String, requestID: String)] = []
    var requestedGitStatusSessionIDs: [(sessionID: String, requestID: String)] = []
    var requestedGitDiffs: [(sessionID: String, path: String, requestID: String)] = []
    var connectCalls: [(host: String, port: Int)] = []
    var connectError: Error?
    var connectStateAfterConnect: ConnectionState?
    var disconnectCallCount = 0
    private var gitRequestCounter = 0

    func connect(host: String, port: Int) async throws {
        connectCalls.append((host: host, port: port))
        if let connectError {
            throw connectError
        }
        state = connectStateAfterConnect ?? .connected
        onStateChange?(state)
    }

    func disconnect() {
        disconnectCallCount += 1
        state = .disconnected
        onStateChange?(state)
    }

    func sendPrompt(_ prompt: String, sessionID: String) async throws {
        sentPrompts.append((prompt: prompt, sessionID: sessionID))
    }

    func respondToApproval(_ approvalID: String, approved: Bool) async throws {
        respondedApprovals.append((approvalID: approvalID, approved: approved))
        pendingApproval = nil
        onPendingApprovalChange?(nil)
    }

    func createSession(name: String, workingDirectory: String) async throws {
        createdSessions.append((name: name, workingDirectory: workingDirectory))
    }

    func cancelTask(sessionID: String) async throws {
        cancelledSessions.append(sessionID)
    }

    func closeSession(id: String) async throws {
        closedSessions.append(id)
    }

    func listDirectory(sessionID: String, path: String) async throws -> String {
        let requestID = nextRequestID("file-list")
        listedDirectories.append((sessionID: sessionID, path: path, requestID: requestID))
        return requestID
    }

    func readFile(sessionID: String, path: String) async throws -> String {
        let requestID = nextRequestID("file-read")
        readFiles.append((sessionID: sessionID, path: path, requestID: requestID))
        return requestID
    }

    func writeFile(sessionID: String, path: String, content: Data) async throws -> String {
        let requestID = nextRequestID("file-write")
        wroteFiles.append((sessionID: sessionID, path: path, content: content, requestID: requestID))
        return requestID
    }

    func createFile(sessionID: String, path: String) async throws -> String {
        let requestID = nextRequestID("file-create")
        createdFiles.append((sessionID: sessionID, path: path, requestID: requestID))
        return requestID
    }

    func createDirectory(sessionID: String, path: String) async throws -> String {
        let requestID = nextRequestID("dir-create")
        createdDirectories.append((sessionID: sessionID, path: path, requestID: requestID))
        return requestID
    }

    func deletePath(sessionID: String, path: String, recursive: Bool) async throws -> String {
        let requestID = nextRequestID("file-delete")
        deletedPaths.append((sessionID: sessionID, path: path, recursive: recursive, requestID: requestID))
        return requestID
    }

    func renamePath(sessionID: String, fromPath: String, toPath: String) async throws -> String {
        let requestID = nextRequestID("file-rename")
        renamedPaths.append((sessionID: sessionID, fromPath: fromPath, toPath: toPath, requestID: requestID))
        return requestID
    }

    func requestGitStatus(sessionID: String) async throws -> String {
        gitRequestCounter += 1
        let requestID = "git-status-\(gitRequestCounter)"
        requestedGitStatusSessionIDs.append((sessionID: sessionID, requestID: requestID))
        return requestID
    }

    func requestGitDiff(sessionID: String, path: String) async throws -> String {
        gitRequestCounter += 1
        let requestID = "git-diff-\(gitRequestCounter)"
        requestedGitDiffs.append((sessionID: sessionID, path: path, requestID: requestID))
        return requestID
    }

    func emitState(_ newState: ConnectionState) {
        state = newState
        onStateChange?(newState)
    }

    func emitMessages(_ newMessages: [ChatMessage]) {
        messages = newMessages
        onMessagesChange?(newMessages)
    }

    func emitPendingApproval(_ approval: Mrt_ApprovalRequest?) {
        pendingApproval = approval
        onPendingApprovalChange?(approval)
    }

    func emitSessions(_ newSessions: [SessionModel]) {
        sessions = newSessions
        onSessionsChange?(newSessions)
    }

    func emitGitStatus(sessionID: String, requestID: String, branch: String, tracking: String, isClean: Bool, changes: [(path: String, status: String)]) {
        var envelope = Mrt_Envelope()
        envelope.requestID = requestID
        envelope.gitResult = .with { result in
            result.sessionID = sessionID
            result.status = .with { status in
                status.branch = branch
                status.tracking = tracking
                status.isClean = isClean
                status.changes = changes.map { entry in
                    .with { change in
                        change.path = entry.path
                        change.status = entry.status
                    }
                }
            }
        }
        onGitResult?(envelope)
    }

    func emitGitDiff(sessionID: String, requestID: String, diff: String) {
        var envelope = Mrt_Envelope()
        envelope.requestID = requestID
        envelope.gitResult = .with { result in
            result.sessionID = sessionID
            result.diff = .with { payload in
                payload.diff = diff
            }
        }
        onGitResult?(envelope)
    }

    func emitGitError(sessionID: String, requestID: String, code: String, message: String) {
        var envelope = Mrt_Envelope()
        envelope.requestID = requestID
        envelope.gitResult = .with { result in
            result.sessionID = sessionID
            result.error = .with { error in
                error.code = code
                error.message = message
                error.fatal = false
            }
        }
        onGitResult?(envelope)
    }

    func emitDirListing(sessionID: String, requestID: String, entries: [(name: String, path: String, isDirectory: Bool)]) {
        var envelope = Mrt_Envelope()
        envelope.requestID = requestID
        envelope.fileResult = .with { result in
            result.sessionID = sessionID
            result.dirListing = .with { listing in
                listing.entries = entries.map { entry in
                    .with { file in
                        file.name = entry.name
                        file.path = entry.path
                        file.isDir = entry.isDirectory
                        file.size = entry.isDirectory ? 0 : 128
                        file.modifiedMs = 1
                    }
                }
            }
        }
        onFileResult?(envelope)
    }

    func emitFileContent(sessionID: String, requestID: String, path: String, content: String, mimeType: String = "text/plain") {
        var envelope = Mrt_Envelope()
        envelope.requestID = requestID
        envelope.fileResult = .with { result in
            result.sessionID = sessionID
            result.fileContent = .with { file in
                file.path = path
                file.content = Data(content.utf8)
                file.mimeType = mimeType
            }
        }
        onFileResult?(envelope)
    }

    func emitFileWriteAck(sessionID: String, requestID: String, path: String) {
        var envelope = Mrt_Envelope()
        envelope.requestID = requestID
        envelope.fileResult = .with { result in
            result.sessionID = sessionID
            result.writeAck = .with { ack in
                ack.path = path
                ack.success = true
            }
        }
        onFileResult?(envelope)
    }

    func emitFileMutationAck(sessionID: String, requestID: String, path: String, message: String) {
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

    func emitFileError(sessionID: String, requestID: String, code: String, message: String) {
        var envelope = Mrt_Envelope()
        envelope.requestID = requestID
        envelope.fileResult = .with { result in
            result.sessionID = sessionID
            result.error = .with { error in
                error.code = code
                error.message = message
                error.fatal = false
            }
        }
        onFileResult?(envelope)
    }

    private func nextRequestID(_ prefix: String) -> String {
        gitRequestCounter += 1
        return "\(prefix)-\(gitRequestCounter)"
    }
}

func makeAgentInfoEnvelope() -> Mrt_Envelope {
    var envelope = Mrt_Envelope()
    envelope.event = .with { event in
        event.agentInfo = .with { info in
            info.agentVersion = "0.1.0"
            info.adapterType = "mock"
            info.hostname = "test-mac"
            info.os = "iOS"
        }
    }
    return envelope
}

func makeCodexOutput(content: String, complete: Bool) -> Mrt_Envelope {
    var envelope = Mrt_Envelope()
    envelope.event = .with { event in
        event.codexOutput = .with { output in
            output.sessionID = "session-1"
            output.content = content
            output.isComplete = complete
        }
    }
    return envelope
}

func makeApprovalRequestEnvelope() -> Mrt_Envelope {
    var envelope = Mrt_Envelope()
    envelope.event = .with { event in
        event.approvalRequest = makeApprovalRequest()
    }
    return envelope
}

func makeApprovalRequest() -> Mrt_ApprovalRequest {
    .with { request in
        request.approvalID = "approval-1"
        request.sessionID = "session-1"
        request.description_p = "Write to file src/main.rs"
        request.command = "echo hi"
    }
}

func makeSessionListEnvelope() -> Mrt_Envelope {
    var envelope = Mrt_Envelope()
    envelope.event = .with { event in
        event.sessionList = .with { update in
            update.sessions = [
                Mrt_SessionInfo.with { session in
                    session.sessionID = "session-1"
                    session.name = "Main"
                    session.workingDir = "/tmp/project"
                }
            ]
        }
    }
    return envelope
}

func makeDeviceRegisterAckEnvelope(success: Bool) -> Mrt_Envelope {
    var envelope = Mrt_Envelope()
    envelope.deviceRegisterAck = .with { ack in
        ack.success = success
        ack.message = success ? "registered" : "invalid auth token"
    }
    return envelope
}

func makeDeviceListResponseEnvelope() -> Mrt_Envelope {
    var envelope = Mrt_Envelope()
    envelope.deviceListResponse = .with { response in
        response.devices = [
            .with { device in
                device.deviceID = "agent-1"
                device.deviceType = .agent
                device.displayName = "Office Mac"
                device.isOnline = true
            }
        ]
    }
    return envelope
}

func makeConnectToDeviceAckEnvelope(success: Bool) -> Mrt_Envelope {
    var envelope = Mrt_Envelope()
    envelope.connectToDeviceAck = .with { ack in
        ack.success = success
        ack.message = success ? "connected" : "device unavailable"
        ack.connectionType = .relay
    }
    return envelope
}

func makeErrorEnvelope(code: String = "CODEX_UNAVAILABLE", message: String = "Codex unavailable", fatal: Bool = false) -> Mrt_Envelope {
    var envelope = Mrt_Envelope()
    envelope.event = .with { event in
        event.error = .with { error in
            error.code = code
            error.message = message
            error.fatal = fatal
        }
    }
    return envelope
}
