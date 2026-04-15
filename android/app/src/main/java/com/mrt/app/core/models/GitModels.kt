package com.mrt.app.core.models

data class GitFileChangeModel(
    val path: String,
    val status: String,
)

data class GitSummaryModel(
    val branch: String,
    val tracking: String,
    val isClean: Boolean,
    val files: List<GitFileChangeModel>,
) {
    companion object {
        fun fromProto(result: mrt.Mrt.GitStatusResult): GitSummaryModel =
            GitSummaryModel(
                branch = result.branch,
                tracking = result.tracking,
                isClean = result.isClean,
                files = result.changesList.map { change ->
                    GitFileChangeModel(
                        path = change.path,
                        status = change.status,
                    )
                },
            )
    }
}

data class GitDiffContent(
    val path: String,
    val rawDiff: String,
)

enum class GitUnavailableReason {
    DISCONNECTED,
    NO_ACTIVE_SESSION,
    SESSION_UNAVAILABLE,
    NOT_REPOSITORY,
}

sealed interface GitDiffState {
    data object Idle : GitDiffState
    data class Loading(val path: String) : GitDiffState
    data class Ready(val content: GitDiffContent) : GitDiffState
    data class Error(val path: String, val message: String) : GitDiffState
}

sealed interface GitViewState {
    data class Unavailable(val reason: GitUnavailableReason) : GitViewState
    data object LoadingStatus : GitViewState
    data class StatusError(val message: String) : GitViewState
    data class ReadyClean(val summary: GitSummaryModel) : GitViewState
    data class ReadyDirty(
        val summary: GitSummaryModel,
        val selectedPath: String,
        val diff: GitDiffState,
    ) : GitViewState
}
