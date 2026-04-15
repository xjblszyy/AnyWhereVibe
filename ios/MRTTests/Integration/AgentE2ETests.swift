@testable import MRT
import Foundation
import XCTest

@MainActor
final class AgentE2ETests: XCTestCase {
    func testMockAgentHappyPathStreamsOutputAndResumesAfterApproval() async throws {
        let endpoint = Endpoint.fromEnvironment()
        let manager = ConnectionManager(
            socket: WebSocketClient(),
            heartbeatInterval: 1,
            timeoutInterval: 5
        )

        var sessionUpdateCount = 0
        manager.onSessionsChange = { _ in
            sessionUpdateCount += 1
        }

        defer {
            manager.disconnect()
        }

        try await manager.connect(host: endpoint.host, port: endpoint.port)

        try await waitUntil("connection reaches .connected", timeout: 5) {
            manager.state == .connected
        }
        try await waitUntil("authoritative session list arrives", timeout: 5) {
            sessionUpdateCount >= 2
        }

        let existingSessionIDs = Set(manager.sessions.map(\.id))
        let sessionName = "E2E \(UUID().uuidString)"
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(sessionName, isDirectory: true)
            .path

        try await manager.createSession(name: sessionName, workingDirectory: workingDirectory)

        let session = try await waitForValue("created session becomes visible", timeout: 5) {
            manager.sessions.first {
                !existingSessionIDs.contains($0.id) && $0.name == sessionName
            }
        }

        let firstPromptMessage = try await sendPromptAndWaitForCompletedOutput(
            prompt: "first smoke prompt",
            sessionID: session.id,
            manager: manager,
            mustObserveStreaming: true
        )
        XCTAssertTrue(firstPromptMessage.content.contains("first smoke prompt"))

        let secondPromptMessage = try await sendPromptAndWaitForCompletedOutput(
            prompt: "second smoke prompt",
            sessionID: session.id,
            manager: manager,
            mustObserveStreaming: false
        )
        XCTAssertTrue(secondPromptMessage.content.contains("second smoke prompt"))

        let thirdPromptBaseline = manager.messages.count
        try await manager.sendPrompt("third smoke prompt", sessionID: session.id)

        let thirdStreamingMessage: ChatMessage = try await waitForValue(
            "third prompt begins streaming",
            timeout: 5
        ) {
            guard let message = latestAssistantMessage(
                after: thirdPromptBaseline,
                sessionID: session.id,
                messages: manager.messages
            ) else {
                return nil
            }
            guard !message.isComplete, !message.content.isEmpty else {
                return nil
            }
            return message
        }
        XCTAssertFalse(thirdStreamingMessage.isComplete)

        let approval: Mrt_ApprovalRequest = try await waitForValue("third prompt asks for approval", timeout: 5) {
            manager.pendingApproval
        }
        XCTAssertEqual(approval.sessionID, session.id)

        try await manager.respondToApproval(approval.approvalID, approved: true)

        try await waitUntil("approval clears after response", timeout: 5) {
            manager.pendingApproval == nil
        }

        let thirdPromptMessage: ChatMessage = try await waitForValue(
            "third prompt completes after approval",
            timeout: 5
        ) {
            guard let message = latestAssistantMessage(
                after: thirdPromptBaseline,
                sessionID: session.id,
                messages: manager.messages
            ) else {
                return nil
            }
            guard message.isComplete else {
                return nil
            }
            return message
        }
        XCTAssertTrue(thirdPromptMessage.content.contains("third smoke prompt"))
        XCTAssertGreaterThan(thirdPromptMessage.content.count, thirdStreamingMessage.content.count)
    }

    private func sendPromptAndWaitForCompletedOutput(
        prompt: String,
        sessionID: String,
        manager: ConnectionManager,
        mustObserveStreaming: Bool
    ) async throws -> ChatMessage {
        let baseline = manager.messages.count
        try await manager.sendPrompt(prompt, sessionID: sessionID)

        if mustObserveStreaming {
            let _: ChatMessage = try await waitForValue("assistant starts streaming for \(prompt)", timeout: 5) {
                guard let message = latestAssistantMessage(
                    after: baseline,
                    sessionID: sessionID,
                    messages: manager.messages
                ) else {
                    return nil
                }
                guard !message.isComplete, !message.content.isEmpty else {
                    return nil
                }
                return message
            }
        }

        return try await waitForValue("assistant completes output for \(prompt)", timeout: 5) {
            guard let message = latestAssistantMessage(
                after: baseline,
                sessionID: sessionID,
                messages: manager.messages
            ) else {
                return nil
            }
            guard message.isComplete else {
                return nil
            }
            return message
        }
    }

    private func latestAssistantMessage(
        after baselineCount: Int,
        sessionID: String,
        messages: [ChatMessage]
    ) -> ChatMessage? {
        guard messages.count > baselineCount else {
            return nil
        }

        return messages.last {
            $0.sessionID == sessionID && $0.role == .assistant
        }
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval,
        pollIntervalNanoseconds: UInt64 = 20_000_000,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        throw AgentE2ETestError.timeout(description)
    }

    private func waitForValue<T>(
        _ description: String,
        timeout: TimeInterval,
        pollIntervalNanoseconds: UInt64 = 20_000_000,
        file: StaticString = #filePath,
        line: UInt = #line,
        value: () -> T?
    ) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = value() {
                return value
            }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        throw AgentE2ETestError.timeout(description)
    }
}

private enum AgentE2ETestError: LocalizedError {
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .timeout(let description):
            return "Timed out waiting for \(description)"
        }
    }
}

private struct Endpoint {
    let host: String
    let port: Int

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Endpoint {
        let host = environment["MRT_E2E_HOST"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let portValue = environment["MRT_E2E_PORT"].flatMap(Int.init)

        return Endpoint(
            host: host?.isEmpty == false ? host! : "127.0.0.1",
            port: portValue ?? 9876
        )
    }
}
