package com.mrt.app.features.files

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.mrt.app.core.models.FileEntryModel
import com.mrt.app.core.models.FileViewerState
import com.mrt.app.core.models.FilesUnavailableReason
import com.mrt.app.core.models.FilesViewState
import com.mrt.app.core.network.ConnectionManaging
import com.mrt.app.core.network.ConnectionState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import mrt.Mrt

class FilesViewModel(
    private val connectionManager: ConnectionManaging,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
) {
    var state by mutableStateOf<FilesViewState>(FilesViewState.Unavailable(FilesUnavailableReason.DISCONNECTED))
        private set
    var draftName by mutableStateOf("")
    var renameDraft by mutableStateOf("")

    private var connectionState: ConnectionState = connectionManager.state.value
    private var activeSessionId: String? = null
    private var isVisible = false
    private var latestListRequestId: String? = null
    private var latestReadRequestId: String? = null
    private var latestMutationRequestId: String? = null
    private var currentPath = ""
    private var currentEntries: List<FileEntryModel> = emptyList()
    private var selectedPath: String? = null
    private var selectedIsDirectory = false
    private var pendingViewerAfterDirectoryLoad: FileViewerState? = null
    private var pendingMutationMessageAfterDirectoryLoad: String? = null

    init {
        scope.launch(context = Dispatchers.Unconfined, start = CoroutineStart.UNDISPATCHED) {
            connectionManager.fileEnvelopes.collectLatest { envelope ->
                envelope?.let(::handleFileEnvelope)
            }
        }
    }

    fun setVisible(visible: Boolean) {
        isVisible = visible
        if (visible) {
            scope.launch(start = CoroutineStart.UNDISPATCHED) { reloadCurrentDirectory() }
        }
    }

    fun updateContext(connectionState: ConnectionState, activeSessionId: String?) {
        val sessionChanged = this.activeSessionId != activeSessionId
        this.connectionState = connectionState
        this.activeSessionId = activeSessionId

        if (sessionChanged) {
            currentPath = ""
            currentEntries = emptyList()
            selectedPath = null
            renameDraft = ""
            latestListRequestId = null
            latestReadRequestId = null
            latestMutationRequestId = null
        }

        if (isVisible) {
            scope.launch(start = CoroutineStart.UNDISPATCHED) { reloadCurrentDirectory() }
        } else {
            updateUnavailableState()
        }
    }

    fun enter(entry: FileEntryModel) {
        selectedPath = entry.path
        selectedIsDirectory = entry.isDirectory
        renameDraft = entry.name

        if (entry.isDirectory) {
            currentPath = entry.path
            scope.launch(start = CoroutineStart.UNDISPATCHED) { reloadCurrentDirectory() }
        } else {
            state = FilesViewState.DirectoryReady(
                path = currentPath,
                entries = currentEntries,
                viewer = FileViewerState.Loading(entry.path),
                mutationMessage = null,
            )
            scope.launch(start = CoroutineStart.UNDISPATCHED) { readFile(entry.path) }
        }
    }

    fun navigateUp() {
        if (currentPath.isEmpty()) return
        currentPath = currentPath.split("/").dropLast(1).joinToString("/")
        selectedPath = null
        renameDraft = ""
        scope.launch(start = CoroutineStart.UNDISPATCHED) { reloadCurrentDirectory() }
    }

    fun updateEditor(text: String) {
        val current = state as? FilesViewState.DirectoryReady ?: return
        val viewer = current.viewer as? FileViewerState.Editable ?: return
        state = current.copy(
            viewer = viewer.copy(content = text),
        )
    }

    fun saveCurrentFile() {
        val current = state as? FilesViewState.DirectoryReady ?: return
        val viewer = current.viewer as? FileViewerState.Editable ?: return
        state = current.copy(
            viewer = viewer.copy(isSaving = true, errorMessage = null),
            mutationMessage = null,
        )
        scope.launch(start = CoroutineStart.UNDISPATCHED) {
            writeFile(viewer.path, viewer.content)
        }
    }

    fun createFile() {
        val candidate = draftName.trim()
        if (candidate.isEmpty()) return
        val path = if (currentPath.isEmpty()) candidate else "$currentPath/$candidate"
        scope.launch(start = CoroutineStart.UNDISPATCHED) {
            mutate { connectionManager.createFile(activeSessionId.orEmpty(), path) }
        }
    }

    fun createDirectory() {
        val candidate = draftName.trim()
        if (candidate.isEmpty()) return
        val path = if (currentPath.isEmpty()) candidate else "$currentPath/$candidate"
        scope.launch(start = CoroutineStart.UNDISPATCHED) {
            mutate { connectionManager.createDirectory(activeSessionId.orEmpty(), path) }
        }
    }

    fun renameSelected() {
        val selectedPath = selectedPath ?: return
        val candidate = renameDraft.trim()
        if (candidate.isEmpty()) return
        val parent = selectedPath.split("/").dropLast(1).joinToString("/")
        val target = if (parent.isEmpty()) candidate else "$parent/$candidate"
        scope.launch(start = CoroutineStart.UNDISPATCHED) {
            mutate { connectionManager.renamePath(activeSessionId.orEmpty(), selectedPath, target) }
        }
    }

    fun deleteSelected() {
        val selectedPath = selectedPath ?: return
        val recursive = selectedIsDirectory
        scope.launch(start = CoroutineStart.UNDISPATCHED) {
            mutate { connectionManager.deletePath(activeSessionId.orEmpty(), selectedPath, recursive) }
        }
    }

    private suspend fun reloadCurrentDirectory() {
        if (!isVisible) return
        if (connectionState != ConnectionState.CONNECTED) {
            state = FilesViewState.Unavailable(FilesUnavailableReason.DISCONNECTED)
            return
        }
        val sessionId = activeSessionId
        if (sessionId.isNullOrBlank()) {
            state = FilesViewState.Unavailable(FilesUnavailableReason.NO_ACTIVE_SESSION)
            return
        }

        pendingViewerAfterDirectoryLoad = currentViewer()
        pendingMutationMessageAfterDirectoryLoad = currentMutationMessage()
        state = FilesViewState.LoadingDirectory(currentPath)
        try {
            latestListRequestId = connectionManager.listDirectory(sessionId, currentPath)
        } catch (_: Throwable) {
            state = FilesViewState.DirectoryError(currentPath, "Failed to load directory.")
        }
    }

    private suspend fun readFile(path: String) {
        val sessionId = activeSessionId ?: return
        try {
            latestReadRequestId = connectionManager.readFile(sessionId, path)
        } catch (_: Throwable) {
            state = FilesViewState.DirectoryReady(currentPath, currentEntries, FileViewerState.Error(path, "Failed to read file."), null)
        }
    }

    private suspend fun writeFile(path: String, content: String) {
        val sessionId = activeSessionId ?: return
        try {
            latestMutationRequestId = connectionManager.writeFile(sessionId, path, content.encodeToByteArray())
        } catch (_: Throwable) {
            state = FilesViewState.DirectoryReady(
                currentPath,
                currentEntries,
                FileViewerState.Editable(path, content, false, "Failed to save file."),
                null,
            )
        }
    }

    private suspend fun mutate(operation: suspend () -> String) {
        try {
            latestMutationRequestId = operation()
        } catch (_: Throwable) {
            state = FilesViewState.DirectoryReady(currentPath, currentEntries, currentViewer(), "File operation failed.")
        }
    }

    private fun handleFileEnvelope(envelope: Mrt.Envelope) {
        if (envelope.payloadCase != Mrt.Envelope.PayloadCase.FILE_RESULT) return
        if (envelope.fileResult.sessionId != (activeSessionId ?: envelope.fileResult.sessionId)) return

        when (envelope.requestId) {
            latestListRequestId -> {
                latestListRequestId = null
                handleListResult(envelope.fileResult)
            }
            latestReadRequestId -> {
                latestReadRequestId = null
                handleReadResult(envelope.fileResult)
            }
            latestMutationRequestId -> {
                latestMutationRequestId = null
                handleMutationResult(envelope.fileResult)
            }
        }
    }

    private fun handleListResult(result: Mrt.FileResult) {
        when (result.resultCase) {
            Mrt.FileResult.ResultCase.DIR_LISTING -> {
                currentEntries = result.dirListing.entriesList.map(FileEntryModel::fromProto)
                val viewer = preservedViewer()
                state = FilesViewState.DirectoryReady(
                    path = currentPath,
                    entries = currentEntries,
                    viewer = viewer,
                    mutationMessage = pendingMutationMessageAfterDirectoryLoad,
                )
                pendingViewerAfterDirectoryLoad = null
                pendingMutationMessageAfterDirectoryLoad = null
            }
            Mrt.FileResult.ResultCase.ERROR -> {
                pendingViewerAfterDirectoryLoad = null
                pendingMutationMessageAfterDirectoryLoad = null
                state = when (result.error.code) {
                    "FILE_SESSION_NOT_FOUND", "FILE_ROOT_INVALID" -> FilesViewState.Unavailable(FilesUnavailableReason.SESSION_UNAVAILABLE)
                    else -> FilesViewState.DirectoryError(currentPath, result.error.message)
                }
            }
            else -> state = FilesViewState.DirectoryError(currentPath, "Unexpected directory response.")
        }
    }

    private fun handleReadResult(result: Mrt.FileResult) {
        when (result.resultCase) {
            Mrt.FileResult.ResultCase.FILE_CONTENT -> {
                state = FilesViewState.DirectoryReady(
                    path = currentPath,
                    entries = currentEntries,
                    viewer = FileViewerState.Editable(
                        path = result.fileContent.path,
                        content = result.fileContent.content.toStringUtf8(),
                        isSaving = false,
                        errorMessage = null,
                    ),
                    mutationMessage = null,
                )
            }
            Mrt.FileResult.ResultCase.ERROR -> {
                val path = selectedPath.orEmpty()
                state = FilesViewState.DirectoryReady(
                    path = currentPath,
                    entries = currentEntries,
                    viewer = if (result.error.code == "FILE_UNSUPPORTED_TYPE" || result.error.code == "FILE_TOO_LARGE") {
                        FileViewerState.ReadOnly(path, result.error.message)
                    } else {
                        FileViewerState.Error(path, result.error.message)
                    },
                    mutationMessage = null,
                )
            }
            else -> state = FilesViewState.DirectoryReady(currentPath, currentEntries, FileViewerState.Error(selectedPath.orEmpty(), "Unexpected file response."), null)
        }
    }

    private fun handleMutationResult(result: Mrt.FileResult) {
        when (result.resultCase) {
            Mrt.FileResult.ResultCase.WRITE_ACK -> {
                val current = state as? FilesViewState.DirectoryReady
                val viewer = current?.viewer as? FileViewerState.Editable
                if (viewer != null) {
                    state = current.copy(
                        viewer = viewer.copy(isSaving = false, errorMessage = null),
                        mutationMessage = "Saved ${result.writeAck.path}.",
                    )
                }
                scope.launch(start = CoroutineStart.UNDISPATCHED) { reloadCurrentDirectory() }
            }
            Mrt.FileResult.ResultCase.MUTATION_ACK -> {
                draftName = ""
                when (result.mutationAck.message.lowercase()) {
                    "renamed" -> {
                        selectedPath = result.mutationAck.path
                        renameDraft = result.mutationAck.path.split("/").last()
                    }
                    "deleted" -> {
                        selectedPath = null
                        selectedIsDirectory = false
                        renameDraft = ""
                    }
                }
                state = FilesViewState.DirectoryReady(
                    path = currentPath,
                    entries = currentEntries,
                    viewer = if (result.mutationAck.message.equals("deleted", true)) FileViewerState.None else currentViewer(),
                    mutationMessage = result.mutationAck.message.replaceFirstChar { it.uppercase() },
                )
                scope.launch(start = CoroutineStart.UNDISPATCHED) { reloadCurrentDirectory() }
            }
            Mrt.FileResult.ResultCase.ERROR -> {
                val current = state as? FilesViewState.DirectoryReady
                val viewer = current?.viewer
                state = if (viewer is FileViewerState.Editable) {
                    FilesViewState.DirectoryReady(
                        path = currentPath,
                        entries = currentEntries,
                        viewer = viewer.copy(isSaving = false, errorMessage = result.error.message),
                        mutationMessage = null,
                    )
                } else {
                    FilesViewState.DirectoryReady(currentPath, currentEntries, currentViewer(), result.error.message)
                }
            }
            else -> state = FilesViewState.DirectoryReady(currentPath, currentEntries, currentViewer(), "Unexpected file mutation response.")
        }
    }

    private fun updateUnavailableState() {
        if (state is FilesViewState.DirectoryReady) return
        state = when {
            connectionState != ConnectionState.CONNECTED -> FilesViewState.Unavailable(FilesUnavailableReason.DISCONNECTED)
            activeSessionId == null -> FilesViewState.Unavailable(FilesUnavailableReason.NO_ACTIVE_SESSION)
            else -> state
        }
    }

    private fun currentViewer(): FileViewerState {
        return (state as? FilesViewState.DirectoryReady)?.viewer ?: FileViewerState.None
    }

    private fun currentMutationMessage(): String? {
        return (state as? FilesViewState.DirectoryReady)?.mutationMessage
    }

    private fun preservedViewer(): FileViewerState {
        val viewer = pendingViewerAfterDirectoryLoad ?: currentViewer()
        val selectedPath = selectedPath
        if (selectedPath != null && currentEntries.none { it.path == selectedPath }) {
            this.selectedPath = null
            this.selectedIsDirectory = false
            this.renameDraft = ""
            return FileViewerState.None
        }
        return viewer
    }
}
