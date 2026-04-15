package com.mrt.app.core.models

data class FileEntryModel(
    val name: String,
    val path: String,
    val isDirectory: Boolean,
    val size: Long,
    val modifiedMs: Long,
) {
    companion object {
        fun fromProto(entry: mrt.Mrt.FileEntry): FileEntryModel =
            FileEntryModel(
                name = entry.name,
                path = entry.path,
                isDirectory = entry.isDir,
                size = entry.size,
                modifiedMs = entry.modifiedMs,
            )
    }
}

enum class FilesUnavailableReason {
    DISCONNECTED,
    NO_ACTIVE_SESSION,
    SESSION_UNAVAILABLE,
}

sealed interface FileViewerState {
    data object None : FileViewerState
    data class Loading(val path: String) : FileViewerState
    data class Editable(
        val path: String,
        val content: String,
        val isSaving: Boolean,
        val errorMessage: String?,
    ) : FileViewerState
    data class ReadOnly(val path: String, val message: String) : FileViewerState
    data class Error(val path: String, val message: String) : FileViewerState
}

sealed interface FilesViewState {
    data class Unavailable(val reason: FilesUnavailableReason) : FilesViewState
    data class LoadingDirectory(val path: String) : FilesViewState
    data class DirectoryError(val path: String, val message: String) : FilesViewState
    data class DirectoryReady(
        val path: String,
        val entries: List<FileEntryModel>,
        val viewer: FileViewerState,
        val mutationMessage: String?,
    ) : FilesViewState
}
