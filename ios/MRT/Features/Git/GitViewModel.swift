import Foundation

@MainActor
final class GitViewModel: ObservableObject {
    @Published private(set) var state: GitViewState = .unavailable(.disconnected)

    private let connectionManager: ConnectionManaging
    private var activeSessionID: String?
    private var connectionState: ConnectionState
    private var isVisible = false
    private var latestStatusRequestID: String?
    private var latestDiffRequestID: String?
    private var latestSummary: GitSummaryModel?
    private var selectedPath: String?

    init(connectionManager: ConnectionManaging) {
        self.connectionManager = connectionManager
        self.connectionState = connectionManager.state
        connectionManager.onGitResult = { [weak self] envelope in
            Task { @MainActor in
                self?.handleGitEnvelope(envelope)
            }
        }
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible {
            Task { await refresh() }
        }
    }

    func updateContext(connectionState: ConnectionState, activeSessionID: String?) {
        let sessionChanged = self.activeSessionID != activeSessionID
        self.connectionState = connectionState
        self.activeSessionID = activeSessionID

        if sessionChanged {
            latestStatusRequestID = nil
            latestDiffRequestID = nil
            latestSummary = nil
            selectedPath = nil
        }

        if isVisible {
            Task { await refresh() }
        } else {
            updateUnavailableState()
        }
    }

    func selectFile(path: String) {
        guard case let .readyDirty(summary, _, _) = state else {
            return
        }
        selectedPath = path
        state = .readyDirty(summary: summary, selectedPath: path, diff: .loading(path: path))
        Task { await requestDiff(path: path) }
    }

    func refresh() async {
        guard isVisible else { return }

        guard connectionState == .connected else {
            state = .unavailable(.disconnected)
            return
        }

        guard let activeSessionID, !activeSessionID.isEmpty else {
            state = .unavailable(.noActiveSession)
            return
        }

        state = .loadingStatus
        do {
            latestStatusRequestID = try await connectionManager.requestGitStatus(sessionID: activeSessionID)
        } catch {
            state = .statusError("Failed to load Git status.")
        }
    }

    private func requestDiff(path: String) async {
        guard let activeSessionID else { return }
        do {
            latestDiffRequestID = try await connectionManager.requestGitDiff(sessionID: activeSessionID, path: path)
        } catch {
            if let summary = latestSummary {
                state = .readyDirty(summary: summary, selectedPath: path, diff: .error(path: path, message: "Failed to load diff."))
            }
        }
    }

    private func handleGitEnvelope(_ envelope: Mrt_Envelope) {
        guard case .gitResult(let result) = envelope.payload else {
            return
        }
        guard result.sessionID == (activeSessionID ?? result.sessionID) else {
            return
        }

        if envelope.requestID == latestStatusRequestID {
            handleStatusResult(result)
        } else if envelope.requestID == latestDiffRequestID {
            handleDiffResult(result)
        }
    }

    private func handleStatusResult(_ result: Mrt_GitResult) {
        latestStatusRequestID = nil
        switch result.result {
        case .status(let status):
            let summary = GitSummaryModel(status)
            latestSummary = summary
            if summary.isClean {
                selectedPath = nil
                latestDiffRequestID = nil
                state = .readyClean(summary)
                return
            }

            let nextPath = summary.files.contains(where: { $0.path == selectedPath }) ? selectedPath! : summary.files.first!.path
            selectedPath = nextPath
            state = .readyDirty(summary: summary, selectedPath: nextPath, diff: .loading(path: nextPath))
            Task { await requestDiff(path: nextPath) }
        case .error(let error):
            switch error.code {
            case "GIT_SESSION_NOT_FOUND":
                state = .unavailable(.sessionUnavailable)
            case "GIT_WORKDIR_INVALID", "GIT_REPO_NOT_FOUND":
                state = .unavailable(.notRepository)
            default:
                state = .statusError(error.message)
            }
        default:
            state = .statusError("Unexpected Git status response.")
        }
    }

    private func handleDiffResult(_ result: Mrt_GitResult) {
        latestDiffRequestID = nil
        guard let summary = latestSummary, let selectedPath else {
            return
        }

        switch result.result {
        case .diff(let diff):
            state = .readyDirty(
                summary: summary,
                selectedPath: selectedPath,
                diff: .ready(GitDiffContent(path: selectedPath, rawDiff: diff.diff))
            )
        case .error(let error):
            state = .readyDirty(
                summary: summary,
                selectedPath: selectedPath,
                diff: .error(path: selectedPath, message: error.message)
            )
        default:
            state = .readyDirty(
                summary: summary,
                selectedPath: selectedPath,
                diff: .error(path: selectedPath, message: "Unexpected Git diff response.")
            )
        }
    }

    private func updateUnavailableState() {
        guard latestSummary == nil else { return }
        if connectionState != .connected {
            state = .unavailable(.disconnected)
        } else if activeSessionID == nil {
            state = .unavailable(.noActiveSession)
        }
    }
}
