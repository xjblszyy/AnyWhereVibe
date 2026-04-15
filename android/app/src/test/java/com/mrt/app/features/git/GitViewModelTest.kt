package com.mrt.app.features.git

import com.mrt.app.core.models.ChatMessage
import com.mrt.app.core.models.GitUnavailableReason
import com.mrt.app.core.models.GitViewState
import com.mrt.app.core.models.SessionModel
import com.mrt.app.core.network.ConnectionManaging
import com.mrt.app.core.network.ConnectionState
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import mrt.Mrt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class GitViewModelTest {
    @Test
    fun gitViewModelShowsUnavailableWithoutConnectedSession() = runTest {
        val connection = FakeGitConnectionManager()
        val viewModel = GitViewModel(connectionManager = connection, scope = backgroundScope)

        viewModel.setVisible(true)
        advanceUntilIdle()

        assertEquals(GitViewState.Unavailable(GitUnavailableReason.DISCONNECTED), viewModel.state)
    }

    @Test
    fun gitViewModelLoadsDirtyStatusAndAutoSelectsFirstFile() = runTest {
        val connection = FakeGitConnectionManager()
        val viewModel = GitViewModel(connectionManager = connection, scope = backgroundScope)

        viewModel.updateContext(ConnectionState.CONNECTED, "session-1")
        viewModel.setVisible(true)
        advanceUntilIdle()

        val request = connection.requestedGitStatusSessionIds.single()
        connection.emitGitStatus(
            sessionId = "session-1",
            requestId = request.requestId,
            branch = "main",
            tracking = "origin/main",
            isClean = false,
            changes = listOf(
                "Sources/App.kt" to "modified",
                "README.md" to "untracked",
            ),
        )
        advanceUntilIdle()

        val diffRequest = connection.requestedGitDiffs.single()
        assertEquals("Sources/App.kt", diffRequest.path)
        connection.emitGitDiff(
            sessionId = "session-1",
            requestId = diffRequest.requestId,
            diff = "@@ -1,1 +1,1 @@\n-old\n+new\n",
        )
        advanceUntilIdle()

        val state = viewModel.state as GitViewState.ReadyDirty
        assertEquals("main", state.summary.branch)
        assertEquals("Sources/App.kt", state.selectedPath)
        assertTrue(state.summary.files.any { it.path == "README.md" })
    }

    @Test
    fun gitViewModelDropsLateResultsAfterSessionChange() = runTest {
        val connection = FakeGitConnectionManager()
        val viewModel = GitViewModel(connectionManager = connection, scope = backgroundScope)

        viewModel.updateContext(ConnectionState.CONNECTED, "session-1")
        viewModel.setVisible(true)
        advanceUntilIdle()
        val staleRequestId = connection.requestedGitStatusSessionIds.last().requestId

        viewModel.updateContext(ConnectionState.CONNECTED, "session-2")
        advanceUntilIdle()

        connection.emitGitStatus(
            sessionId = "session-1",
            requestId = staleRequestId,
            branch = "main",
            tracking = "",
            isClean = false,
            changes = listOf("old.kt" to "modified"),
        )
        advanceUntilIdle()

        assertEquals("session-2", connection.requestedGitStatusSessionIds.last().sessionId)
        assertEquals(GitViewState.LoadingStatus, viewModel.state)
    }

    @Test
    fun gitViewModelSeparatesDisconnectedNoSessionAndNotRepoStates() = runTest {
        val connection = FakeGitConnectionManager()
        val viewModel = GitViewModel(connectionManager = connection, scope = backgroundScope)

        viewModel.setVisible(true)
        advanceUntilIdle()
        assertEquals(GitViewState.Unavailable(GitUnavailableReason.DISCONNECTED), viewModel.state)

        viewModel.updateContext(ConnectionState.CONNECTED, null)
        viewModel.setVisible(true)
        advanceUntilIdle()
        assertEquals(GitViewState.Unavailable(GitUnavailableReason.NO_ACTIVE_SESSION), viewModel.state)

        viewModel.updateContext(ConnectionState.CONNECTED, "session-1")
        advanceUntilIdle()
        val requestId = connection.requestedGitStatusSessionIds.last().requestId
        connection.emitGitError(
            sessionId = "session-1",
            requestId = requestId,
            code = "GIT_REPO_NOT_FOUND",
            message = "not a repository",
        )
        advanceUntilIdle()
        assertEquals(GitViewState.Unavailable(GitUnavailableReason.NOT_REPOSITORY), viewModel.state)
    }
}

private class FakeGitConnectionManager : ConnectionManaging {
    private val _state = MutableStateFlow(ConnectionState.DISCONNECTED)
    override val state: StateFlow<ConnectionState> = _state.asStateFlow()

    private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
    override val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

    private val _pendingApproval = MutableStateFlow<Mrt.ApprovalRequest?>(null)
    override val pendingApproval: StateFlow<Mrt.ApprovalRequest?> = _pendingApproval.asStateFlow()

    private val _sessions = MutableStateFlow<List<SessionModel>>(emptyList())
    override val sessions: StateFlow<List<SessionModel>> = _sessions.asStateFlow()

    private val _gitEnvelopes = MutableStateFlow<Mrt.Envelope?>(null)
    override val gitEnvelopes: StateFlow<Mrt.Envelope?> = _gitEnvelopes.asStateFlow()

    val requestedGitStatusSessionIds = mutableListOf<GitStatusRequest>()
    val requestedGitDiffs = mutableListOf<GitDiffRequest>()
    private var counter = 0

    override suspend fun connect(host: String, port: Int) = Unit
    override fun disconnect() = Unit
    override suspend fun sendPrompt(prompt: String, sessionId: String) = Unit
    override suspend fun respondToApproval(approvalId: String, approved: Boolean) = Unit
    override suspend fun cancelTask(sessionId: String) = Unit
    override suspend fun switchSession(sessionId: String) = Unit
    override suspend fun createSession(name: String, workingDirectory: String) = Unit
    override suspend fun closeSession(sessionId: String) = Unit

    override suspend fun requestGitStatus(sessionId: String): String {
        counter += 1
        val requestId = "git-status-$counter"
        requestedGitStatusSessionIds += GitStatusRequest(sessionId, requestId)
        return requestId
    }

    override suspend fun requestGitDiff(sessionId: String, path: String): String {
        counter += 1
        val requestId = "git-diff-$counter"
        requestedGitDiffs += GitDiffRequest(sessionId, path, requestId)
        return requestId
    }

    fun emitGitStatus(
        sessionId: String,
        requestId: String,
        branch: String,
        tracking: String,
        isClean: Boolean,
        changes: List<Pair<String, String>>,
    ) {
        _gitEnvelopes.value = Mrt.Envelope.newBuilder()
            .setRequestId(requestId)
            .setGitResult(
                Mrt.GitResult.newBuilder()
                    .setSessionId(sessionId)
                    .setStatus(
                        Mrt.GitStatusResult.newBuilder()
                            .setBranch(branch)
                            .setTracking(tracking)
                            .setIsClean(isClean)
                            .addAllChanges(
                                changes.map { (path, status) ->
                                    Mrt.GitFileChange.newBuilder()
                                        .setPath(path)
                                        .setStatus(status)
                                        .build()
                                },
                            )
                            .build(),
                    )
                    .build(),
            )
            .build()
    }

    fun emitGitDiff(sessionId: String, requestId: String, diff: String) {
        _gitEnvelopes.value = Mrt.Envelope.newBuilder()
            .setRequestId(requestId)
            .setGitResult(
                Mrt.GitResult.newBuilder()
                    .setSessionId(sessionId)
                    .setDiff(Mrt.GitDiffResult.newBuilder().setDiff(diff).build())
                    .build(),
            )
            .build()
    }

    fun emitGitError(sessionId: String, requestId: String, code: String, message: String) {
        _gitEnvelopes.value = Mrt.Envelope.newBuilder()
            .setRequestId(requestId)
            .setGitResult(
                Mrt.GitResult.newBuilder()
                    .setSessionId(sessionId)
                    .setError(
                        Mrt.ErrorEvent.newBuilder()
                            .setCode(code)
                            .setMessage(message)
                            .setFatal(false)
                            .build(),
                    )
                    .build(),
            )
            .build()
    }

    data class GitStatusRequest(val sessionId: String, val requestId: String)
    data class GitDiffRequest(val sessionId: String, val path: String, val requestId: String)
}
