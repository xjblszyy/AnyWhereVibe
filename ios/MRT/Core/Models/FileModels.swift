import Foundation

struct FileEntryModel: Identifiable, Equatable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: UInt64
    let modifiedMs: UInt64

    var id: String { path.ifEmpty(name) }

    init(_ entry: Mrt_FileEntry) {
        self.name = entry.name
        self.path = entry.path
        self.isDirectory = entry.isDir
        self.size = entry.size
        self.modifiedMs = entry.modifiedMs
    }
}

enum FilesUnavailableReason: Equatable {
    case disconnected
    case noActiveSession
    case sessionUnavailable
}

enum FileViewerState: Equatable {
    case none
    case loading(path: String)
    case editable(path: String, content: String, isSaving: Bool, errorMessage: String?)
    case readOnly(path: String, message: String)
    case error(path: String, message: String)
}

enum FilesViewState: Equatable {
    case unavailable(FilesUnavailableReason)
    case loadingDirectory(path: String)
    case directoryError(path: String, message: String)
    case directoryReady(path: String, entries: [FileEntryModel], viewer: FileViewerState, mutationMessage: String?)
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
