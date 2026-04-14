@testable import MRT
import Foundation
import SwiftProtobuf

final class StubWebSocketClient: WebSocketClientProtocol {
    var sentData: [Data] = []
    var connectedURL: URL?
    var connectCalls: [URL] = []
    var disconnectCallCount = 0
    var onReceive: ((Data) -> Void)?
    var onClose: (() -> Void)?

    func connect(url: URL) async throws {
        connectedURL = url
        connectCalls.append(url)
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
    var sentPrompts: [(prompt: String, sessionID: String)] = []

    func connect(host: String, port: Int) async throws {
        state = .connected
    }

    func disconnect() {
        state = .disconnected
    }

    func sendPrompt(_ prompt: String, sessionID: String) async throws {
        sentPrompts.append((prompt: prompt, sessionID: sessionID))
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
        event.approvalRequest = .with { request in
            request.approvalID = "approval-1"
            request.sessionID = "session-1"
            request.description_p = "Write to file src/main.rs"
            request.command = "echo hi"
        }
    }
    return envelope
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
