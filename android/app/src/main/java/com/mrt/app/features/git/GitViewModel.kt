package com.mrt.app.features.git

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.mrt.app.core.models.GitDiffContent
import com.mrt.app.core.models.GitDiffState
import com.mrt.app.core.models.GitSummaryModel
import com.mrt.app.core.models.GitUnavailableReason
import com.mrt.app.core.models.GitViewState
import com.mrt.app.core.network.ConnectionManaging
import com.mrt.app.core.network.ConnectionState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import mrt.Mrt

class GitViewModel(
    private val connectionManager: ConnectionManaging,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
) {
    var state by mutableStateOf<GitViewState>(GitViewState.Unavailable(GitUnavailableReason.DISCONNECTED))
        private set

    private var activeSessionId: String? = null
    private var connectionState: ConnectionState = connectionManager.state.value
    private var isVisible: Boolean = false
    private var latestStatusRequestId: String? = null
    private var latestDiffRequestId: String? = null
    private var latestSummary: GitSummaryModel? = null
    private var selectedPath: String? = null

    init {
        scope.launch(context = Dispatchers.Unconfined, start = CoroutineStart.UNDISPATCHED) {
            connectionManager.gitEnvelopes.collectLatest { envelope ->
                envelope?.let(::handleGitEnvelope)
            }
        }
    }

    fun setVisible(visible: Boolean) {
        isVisible = visible
        if (visible) {
            scope.launch(start = CoroutineStart.UNDISPATCHED) { refresh() }
        }
    }

    fun updateContext(connectionState: ConnectionState, activeSessionId: String?) {
        val sessionChanged = this.activeSessionId != activeSessionId
        this.connectionState = connectionState
        this.activeSessionId = activeSessionId

        if (sessionChanged) {
            latestStatusRequestId = null
            latestDiffRequestId = null
            latestSummary = null
            selectedPath = null
        }

        if (isVisible) {
            scope.launch(start = CoroutineStart.UNDISPATCHED) { refresh() }
        } else {
            updateUnavailableState()
        }
    }

    fun selectFile(path: String) {
        val current = state
        if (current !is GitViewState.ReadyDirty) {
            return
        }

        selectedPath = path
        state = current.copy(selectedPath = path, diff = GitDiffState.Loading(path))
        scope.launch(start = CoroutineStart.UNDISPATCHED) { requestDiff(path) }
    }

    suspend fun refresh() {
        if (!isVisible) {
            return
        }

        if (connectionState != ConnectionState.CONNECTED) {
            state = GitViewState.Unavailable(GitUnavailableReason.DISCONNECTED)
            return
        }

        val sessionId = activeSessionId
        if (sessionId.isNullOrBlank()) {
            state = GitViewState.Unavailable(GitUnavailableReason.NO_ACTIVE_SESSION)
            return
        }

        state = GitViewState.LoadingStatus
        try {
            latestStatusRequestId = connectionManager.requestGitStatus(sessionId)
        } catch (_: Throwable) {
            state = GitViewState.StatusError("Failed to load Git status.")
        }
    }

    private suspend fun requestDiff(path: String) {
        val sessionId = activeSessionId ?: return
        try {
            latestDiffRequestId = connectionManager.requestGitDiff(sessionId, path)
        } catch (_: Throwable) {
            val summary = latestSummary ?: return
            state = GitViewState.ReadyDirty(summary, path, GitDiffState.Error(path, "Failed to load diff."))
        }
    }

    private fun handleGitEnvelope(envelope: Mrt.Envelope) {
        if (envelope.payloadCase != Mrt.Envelope.PayloadCase.GIT_RESULT) {
            return
        }
        if (envelope.gitResult.sessionId != (activeSessionId ?: envelope.gitResult.sessionId)) {
            return
        }

        when (envelope.requestId) {
            latestStatusRequestId -> handleStatusResult(envelope.gitResult)
            latestDiffRequestId -> handleDiffResult(envelope.gitResult)
        }
    }

    private fun handleStatusResult(result: Mrt.GitResult) {
        latestStatusRequestId = null
        when (result.resultCase) {
            Mrt.GitResult.ResultCase.STATUS -> {
                val summary = GitSummaryModel.fromProto(result.status)
                latestSummary = summary
                if (summary.isClean) {
                    selectedPath = null
                    latestDiffRequestId = null
                    state = GitViewState.ReadyClean(summary)
                    return
                }

                val nextPath = if (summary.files.any { it.path == selectedPath }) {
                    selectedPath ?: summary.files.first().path
                } else {
                    summary.files.first().path
                }
                selectedPath = nextPath
                state = GitViewState.ReadyDirty(summary, nextPath, GitDiffState.Loading(nextPath))
                scope.launch(start = CoroutineStart.UNDISPATCHED) { requestDiff(nextPath) }
            }

            Mrt.GitResult.ResultCase.ERROR -> {
                state = when (result.error.code) {
                    "GIT_SESSION_NOT_FOUND" -> GitViewState.Unavailable(GitUnavailableReason.SESSION_UNAVAILABLE)
                    "GIT_WORKDIR_INVALID", "GIT_REPO_NOT_FOUND" -> GitViewState.Unavailable(GitUnavailableReason.NOT_REPOSITORY)
                    else -> GitViewState.StatusError(result.error.message)
                }
            }

            else -> state = GitViewState.StatusError("Unexpected Git status response.")
        }
    }

    private fun handleDiffResult(result: Mrt.GitResult) {
        latestDiffRequestId = null
        val summary = latestSummary ?: return
        val path = selectedPath ?: return

        state = when (result.resultCase) {
            Mrt.GitResult.ResultCase.DIFF -> GitViewState.ReadyDirty(
                summary = summary,
                selectedPath = path,
                diff = GitDiffState.Ready(GitDiffContent(path, result.diff.diff)),
            )

            Mrt.GitResult.ResultCase.ERROR -> GitViewState.ReadyDirty(
                summary = summary,
                selectedPath = path,
                diff = GitDiffState.Error(path, result.error.message),
            )

            else -> GitViewState.ReadyDirty(
                summary = summary,
                selectedPath = path,
                diff = GitDiffState.Error(path, "Unexpected Git diff response."),
            )
        }
    }

    private fun updateUnavailableState() {
        if (latestSummary != null) {
            return
        }
        state = when {
            connectionState != ConnectionState.CONNECTED -> GitViewState.Unavailable(GitUnavailableReason.DISCONNECTED)
            activeSessionId == null -> GitViewState.Unavailable(GitUnavailableReason.NO_ACTIVE_SESSION)
            else -> state
        }
    }
}
