@testable import MRT
import XCTest

final class GitViewModelTests: XCTestCase {
    @MainActor
    func testGitViewModelShowsUnavailableWithoutConnectedSession() async {
        let connection = StubConnectionManager()
        let viewModel = GitViewModel(connectionManager: connection)

        viewModel.setVisible(true)

        XCTAssertEqual(viewModel.state, .unavailable(.disconnected))
    }

    @MainActor
    func testGitViewModelLoadsDirtyStatusAndAutoSelectsFirstFile() async throws {
        let connection = StubConnectionManager()
        let viewModel = GitViewModel(connectionManager: connection)

        viewModel.updateContext(connectionState: .connected, activeSessionID: "session-1")
        viewModel.setVisible(true)
        try? await Task.sleep(nanoseconds: 20_000_000)

        let request = try XCTUnwrap(connection.requestedGitStatusSessionIDs.last)
        connection.emitGitStatus(
            sessionID: "session-1",
            requestID: request.requestID,
            branch: "main",
            tracking: "origin/main",
            isClean: false,
            changes: [
                ("Sources/App.swift", "modified"),
                ("README.md", "untracked"),
            ]
        )
        try? await Task.sleep(nanoseconds: 20_000_000)

        let diffRequest = try XCTUnwrap(connection.requestedGitDiffs.last)
        XCTAssertEqual(diffRequest.path, "Sources/App.swift")
        connection.emitGitDiff(
            sessionID: "session-1",
            requestID: diffRequest.requestID,
            diff: "@@ -1,1 +1,1 @@\n-old\n+new\n"
        )
        try? await Task.sleep(nanoseconds: 20_000_000)

        guard case let .readyDirty(summary, selectedPath, diff) = viewModel.state else {
            return XCTFail("expected dirty git state")
        }
        XCTAssertEqual(summary.branch, "main")
        XCTAssertEqual(selectedPath, "Sources/App.swift")
        XCTAssertEqual(summary.files.map(\.path), ["Sources/App.swift", "README.md"])
        XCTAssertEqual(diff, .ready(GitDiffContent(path: "Sources/App.swift", rawDiff: "@@ -1,1 +1,1 @@\n-old\n+new\n")))
    }

    @MainActor
    func testGitViewModelDropsLateResultsAfterSessionChange() async throws {
        let connection = StubConnectionManager()
        let viewModel = GitViewModel(connectionManager: connection)

        viewModel.updateContext(connectionState: .connected, activeSessionID: "session-1")
        viewModel.setVisible(true)
        try? await Task.sleep(nanoseconds: 20_000_000)

        let staleRequestID = try XCTUnwrap(connection.requestedGitStatusSessionIDs.last?.requestID)

        viewModel.updateContext(connectionState: .connected, activeSessionID: "session-2")
        try? await Task.sleep(nanoseconds: 20_000_000)

        connection.emitGitStatus(
            sessionID: "session-1",
            requestID: staleRequestID,
            branch: "main",
            tracking: "",
            isClean: false,
            changes: [("old.swift", "modified")]
        )
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(connection.requestedGitStatusSessionIDs.last?.sessionID, "session-2")
        XCTAssertEqual(viewModel.state, .loadingStatus)
    }

    @MainActor
    func testGitViewModelSeparatesDisconnectedNoSessionAndNotRepoStates() async throws {
        let connection = StubConnectionManager()
        let viewModel = GitViewModel(connectionManager: connection)

        viewModel.setVisible(true)
        XCTAssertEqual(viewModel.state, .unavailable(.disconnected))

        viewModel.updateContext(connectionState: .connected, activeSessionID: nil)
        viewModel.setVisible(true)
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(viewModel.state, .unavailable(.noActiveSession))

        viewModel.updateContext(connectionState: .connected, activeSessionID: "session-1")
        try? await Task.sleep(nanoseconds: 20_000_000)
        let requestID = try XCTUnwrap(connection.requestedGitStatusSessionIDs.last?.requestID)
        connection.emitGitError(
            sessionID: "session-1",
            requestID: requestID,
            code: "GIT_REPO_NOT_FOUND",
            message: "not a repository"
        )
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(viewModel.state, .unavailable(.notRepository))
    }
}
