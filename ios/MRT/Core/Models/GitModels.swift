import Foundation

struct GitFileChangeModel: Identifiable, Equatable {
    let path: String
    let status: String

    var id: String { path }
}

struct GitSummaryModel: Equatable {
    let branch: String
    let tracking: String
    let isClean: Bool
    let files: [GitFileChangeModel]

    init(_ result: Mrt_GitStatusResult) {
        branch = result.branch
        tracking = result.tracking
        isClean = result.isClean
        files = result.changes.map { change in
            GitFileChangeModel(path: change.path, status: change.status)
        }
    }
}

struct GitDiffContent: Equatable {
    let path: String
    let rawDiff: String
}

enum GitUnavailableReason: Equatable {
    case disconnected
    case noActiveSession
    case sessionUnavailable
    case notRepository
}

enum GitDiffState: Equatable {
    case idle
    case loading(path: String)
    case ready(GitDiffContent)
    case error(path: String, message: String)
}

enum GitViewState: Equatable {
    case unavailable(GitUnavailableReason)
    case loadingStatus
    case statusError(String)
    case readyClean(GitSummaryModel)
    case readyDirty(summary: GitSummaryModel, selectedPath: String, diff: GitDiffState)
}
