import Foundation

@MainActor
final class FilesViewModel: ObservableObject {
    @Published private(set) var state: FilesViewState = .unavailable(.disconnected)
    @Published var draftName = ""
    @Published var renameDraft = ""

    private let connectionManager: ConnectionManaging
    private var connectionState: ConnectionState
    private var activeSessionID: String?
    private var isVisible = false
    private var latestListRequestID: String?
    private var latestReadRequestID: String?
    private var latestMutationRequestID: String?
    private var currentPath = ""
    private var currentEntries: [FileEntryModel] = []
    private var selectedPath: String?
    private var selectedIsDirectory = false
    private var pendingViewerAfterDirectoryLoad: FileViewerState?
    private var pendingMutationMessageAfterDirectoryLoad: String?

    init(connectionManager: ConnectionManaging) {
        self.connectionManager = connectionManager
        self.connectionState = connectionManager.state
        connectionManager.onFileResult = { [weak self] envelope in
            Task { @MainActor in
                self?.handleFileEnvelope(envelope)
            }
        }
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible {
            Task { await reloadCurrentDirectory() }
        }
    }

    func updateContext(connectionState: ConnectionState, activeSessionID: String?) {
        let sessionChanged = self.activeSessionID != activeSessionID
        self.connectionState = connectionState
        self.activeSessionID = activeSessionID

        if sessionChanged {
            currentPath = ""
            currentEntries = []
            selectedPath = nil
            renameDraft = ""
            latestListRequestID = nil
            latestReadRequestID = nil
            latestMutationRequestID = nil
        }

        if isVisible {
            Task { await reloadCurrentDirectory() }
        } else {
            updateUnavailableState()
        }
    }

    func enter(_ entry: FileEntryModel) {
        selectedPath = entry.path
        selectedIsDirectory = entry.isDirectory
        renameDraft = entry.name

        if entry.isDirectory {
            currentPath = entry.path
            Task { await reloadCurrentDirectory() }
        } else {
            state = .directoryReady(path: currentPath, entries: currentEntries, viewer: .loading(path: entry.path), mutationMessage: nil)
            Task { await readFile(path: entry.path) }
        }
    }

    func navigateUp() {
        guard !currentPath.isEmpty else { return }
        let parts = currentPath.split(separator: "/").dropLast()
        currentPath = parts.joined(separator: "/")
        selectedPath = nil
        renameDraft = ""
        Task { await reloadCurrentDirectory() }
    }

    func saveCurrentFile() {
        guard case let .directoryReady(path, entries, .editable(filePath, content, _, _), _) = state else {
            return
        }
        state = .directoryReady(
            path: path,
            entries: entries,
            viewer: .editable(path: filePath, content: content, isSaving: true, errorMessage: nil),
            mutationMessage: nil
        )
        Task { await writeFile(path: filePath, content: content) }
    }

    func updateEditor(_ text: String) {
        guard case let .directoryReady(path, entries, .editable(filePath, _, isSaving, errorMessage), mutationMessage) = state else {
            return
        }
        state = .directoryReady(
            path: path,
            entries: entries,
            viewer: .editable(path: filePath, content: text, isSaving: isSaving, errorMessage: errorMessage),
            mutationMessage: mutationMessage
        )
    }

    func createFile() {
        let candidate = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        let path = currentPath.isEmpty ? candidate : "\(currentPath)/\(candidate)"
        Task { await mutate { try await connectionManager.createFile(sessionID: activeSessionID ?? "", path: path) } }
    }

    func createDirectory() {
        let candidate = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        let path = currentPath.isEmpty ? candidate : "\(currentPath)/\(candidate)"
        Task { await mutate { try await connectionManager.createDirectory(sessionID: activeSessionID ?? "", path: path) } }
    }

    func renameSelected() {
        guard let selectedPath else { return }
        let candidate = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        let parent = parentPath(of: selectedPath)
        let target = parent.isEmpty ? candidate : "\(parent)/\(candidate)"
        Task { await mutate { try await connectionManager.renamePath(sessionID: activeSessionID ?? "", fromPath: selectedPath, toPath: target) } }
    }

    func deleteSelected() {
        guard let selectedPath else { return }
        let recursive = selectedIsDirectory
        Task { await mutate { try await connectionManager.deletePath(sessionID: activeSessionID ?? "", path: selectedPath, recursive: recursive) } }
    }

    private func reloadCurrentDirectory() async {
        guard isVisible else { return }
        guard connectionState == .connected else {
            state = .unavailable(.disconnected)
            return
        }
        guard let sessionID = activeSessionID, !sessionID.isEmpty else {
            state = .unavailable(.noActiveSession)
            return
        }

        pendingViewerAfterDirectoryLoad = currentViewer()
        pendingMutationMessageAfterDirectoryLoad = mutationMessage(from: state)
        state = .loadingDirectory(path: currentPath)
        do {
            latestListRequestID = try await connectionManager.listDirectory(sessionID: sessionID, path: currentPath)
        } catch {
            state = .directoryError(path: currentPath, message: "Failed to load directory.")
        }
    }

    private func readFile(path: String) async {
        guard let sessionID = activeSessionID else { return }
        do {
            latestReadRequestID = try await connectionManager.readFile(sessionID: sessionID, path: path)
        } catch {
            state = .directoryReady(path: currentPath, entries: currentEntries, viewer: .error(path: path, message: "Failed to read file."), mutationMessage: nil)
        }
    }

    private func writeFile(path: String, content: String) async {
        guard let sessionID = activeSessionID else { return }
        do {
            latestMutationRequestID = try await connectionManager.writeFile(sessionID: sessionID, path: path, content: Data(content.utf8))
        } catch {
            state = .directoryReady(
                path: currentPath,
                entries: currentEntries,
                viewer: .editable(path: path, content: content, isSaving: false, errorMessage: "Failed to save file."),
                mutationMessage: nil
            )
        }
    }

    private func mutate(_ operation: () async throws -> String) async {
        do {
            latestMutationRequestID = try await operation()
        } catch {
            state = .directoryReady(path: currentPath, entries: currentEntries, viewer: currentViewer(), mutationMessage: "File operation failed.")
        }
    }

    private func handleFileEnvelope(_ envelope: Mrt_Envelope) {
        guard case .fileResult(let result) = envelope.payload else { return }
        guard result.sessionID == (activeSessionID ?? result.sessionID) else { return }

        switch envelope.requestID {
        case latestListRequestID:
            latestListRequestID = nil
            handleListResult(result)
        case latestReadRequestID:
            latestReadRequestID = nil
            handleReadResult(result)
        case latestMutationRequestID:
            latestMutationRequestID = nil
            handleMutationResult(result)
        default:
            break
        }
    }

    private func handleListResult(_ result: Mrt_FileResult) {
        switch result.result {
        case .dirListing(let listing):
            currentEntries = listing.entries.map(FileEntryModel.init)
            let preservedViewer: FileViewerState = {
                let candidate = pendingViewerAfterDirectoryLoad ?? currentViewer()
                guard let selectedPath,
                      currentEntries.contains(where: { $0.path == selectedPath }) else {
                    self.selectedPath = nil
                    self.selectedIsDirectory = false
                    self.renameDraft = ""
                    return .none
                }
                switch candidate {
                case .editable, .loading, .readOnly, .error:
                    return candidate
                case .none:
                    return .none
                }
            }()
            state = .directoryReady(
                path: currentPath,
                entries: currentEntries,
                viewer: preservedViewer,
                mutationMessage: pendingMutationMessageAfterDirectoryLoad
            )
            pendingViewerAfterDirectoryLoad = nil
            pendingMutationMessageAfterDirectoryLoad = nil
        case .error(let error):
            pendingViewerAfterDirectoryLoad = nil
            pendingMutationMessageAfterDirectoryLoad = nil
            switch error.code {
            case "FILE_SESSION_NOT_FOUND", "FILE_ROOT_INVALID":
                state = .unavailable(.sessionUnavailable)
            default:
                state = .directoryError(path: currentPath, message: error.message)
            }
        default:
            state = .directoryError(path: currentPath, message: "Unexpected directory response.")
        }
    }

    private func handleReadResult(_ result: Mrt_FileResult) {
        switch result.result {
        case .fileContent(let content):
            let text = String(data: content.content, encoding: .utf8) ?? ""
            state = .directoryReady(path: currentPath, entries: currentEntries, viewer: .editable(path: content.path, content: text, isSaving: false, errorMessage: nil), mutationMessage: nil)
        case .error(let error):
            let path = selectedPath ?? ""
            if error.code == "FILE_UNSUPPORTED_TYPE" || error.code == "FILE_TOO_LARGE" {
                state = .directoryReady(path: currentPath, entries: currentEntries, viewer: .readOnly(path: path, message: error.message), mutationMessage: nil)
            } else {
                state = .directoryReady(path: currentPath, entries: currentEntries, viewer: .error(path: path, message: error.message), mutationMessage: nil)
            }
        default:
            state = .directoryReady(path: currentPath, entries: currentEntries, viewer: .error(path: selectedPath ?? "", message: "Unexpected file response."), mutationMessage: nil)
        }
    }

    private func handleMutationResult(_ result: Mrt_FileResult) {
        switch result.result {
        case .writeAck(let ack):
            if case let .directoryReady(path, entries, .editable(filePath, content, _, _), _) = state {
                state = .directoryReady(path: path, entries: entries, viewer: .editable(path: filePath, content: content, isSaving: false, errorMessage: nil), mutationMessage: "Saved \(ack.path).")
            }
            Task { await reloadCurrentDirectory() }
        case .mutationAck(let ack):
            draftName = ""
            let currentViewer = currentViewer()
            switch ack.message.lowercased() {
            case "renamed":
                selectedPath = ack.path
                selectedIsDirectory = currentEntries.first(where: { $0.path == ack.path })?.isDirectory ?? selectedIsDirectory
                renameDraft = ack.path.split(separator: "/").last.map(String.init) ?? ack.path
            case "deleted":
                selectedPath = nil
                selectedIsDirectory = false
                renameDraft = ""
            default:
                break
            }
            state = .directoryReady(path: currentPath, entries: currentEntries, viewer: ifDeletedViewer(ack.message, currentViewer), mutationMessage: ack.message.capitalized)
            Task { await reloadCurrentDirectory() }
        case .error(let error):
            switch state {
            case let .directoryReady(path, entries, .editable(filePath, content, isSaving, _), _):
                state = .directoryReady(path: path, entries: entries, viewer: .editable(path: filePath, content: content, isSaving: false, errorMessage: error.message), mutationMessage: nil)
            default:
                state = .directoryReady(path: currentPath, entries: currentEntries, viewer: currentViewer(), mutationMessage: error.message)
            }
        default:
            state = .directoryReady(path: currentPath, entries: currentEntries, viewer: currentViewer(), mutationMessage: "Unexpected file mutation response.")
        }
    }

    private func currentViewer() -> FileViewerState {
        if case let .directoryReady(_, _, viewer, _) = state {
            return viewer
        }
        return .none
    }

    private func updateUnavailableState() {
        if case .directoryReady = state { return }
        if connectionState != .connected {
            state = .unavailable(.disconnected)
        } else if activeSessionID == nil {
            state = .unavailable(.noActiveSession)
        }
    }

    private func parentPath(of path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }

    private func mutationMessage(from state: FilesViewState) -> String? {
        if case let .directoryReady(_, _, _, mutationMessage) = state {
            return mutationMessage
        }
        return nil
    }

    private func ifDeletedViewer(_ message: String, _ current: FileViewerState) -> FileViewerState {
        message.lowercased() == "deleted" ? .none : current
    }
}
