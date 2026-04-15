package com.mrt.app.features.git

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.mrt.app.core.models.ChatMessage
import com.mrt.app.core.models.SessionModel
import com.mrt.app.core.network.ConnectionManaging
import com.mrt.app.core.network.ConnectionState
import com.mrt.app.designsystem.theme.MRTTheme
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import mrt.Mrt
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GitScreenInstrumentedTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun gitScreenShowsChangedFilesAndDiff() {
        val connectionManager = FakeGitConnectionManager()
        val viewModel = GitViewModel(connectionManager = connectionManager)

        composeRule.setContent {
            MRTTheme(darkTheme = true) {
                GitScreen(viewModel = viewModel)
            }
        }

        composeRule.runOnIdle {
            viewModel.updateContext(ConnectionState.CONNECTED, "session-1")
            viewModel.setVisible(true)
        }
        composeRule.waitUntil {
            connectionManager.statusRequests.isNotEmpty()
        }
        val statusRequestId = connectionManager.statusRequests.last().requestId
        composeRule.runOnIdle {
            connectionManager.emitGitStatus(
                sessionId = "session-1",
                requestId = statusRequestId,
                branch = "main",
                tracking = "origin/main",
                isClean = false,
                changes = listOf("Sources/App.kt" to "modified"),
            )
        }
        composeRule.waitUntil {
            connectionManager.diffRequests.isNotEmpty()
        }
        val diffRequestId = connectionManager.diffRequests.last().requestId
        composeRule.runOnIdle {
            connectionManager.emitGitDiff(
                sessionId = "session-1",
                requestId = diffRequestId,
                diff = "diff --git a/Sources/App.kt b/Sources/App.kt\n@@ -1,1 +1,1 @@\n-old\n+new\n",
            )
        }

        composeRule.onNodeWithTag("gitDiff").fetchSemanticsNode()
    }

    private class FakeGitConnectionManager : ConnectionManaging {
        private val _state = MutableStateFlow(ConnectionState.CONNECTED)
        override val state: StateFlow<ConnectionState> = _state.asStateFlow()

        private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
        override val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

        private val _pendingApproval = MutableStateFlow<Mrt.ApprovalRequest?>(null)
        override val pendingApproval: StateFlow<Mrt.ApprovalRequest?> = _pendingApproval.asStateFlow()

        private val _sessions = MutableStateFlow<List<SessionModel>>(emptyList())
        override val sessions: StateFlow<List<SessionModel>> = _sessions.asStateFlow()

        private val _gitEnvelopes = MutableStateFlow<Mrt.Envelope?>(null)
        override val gitEnvelopes: StateFlow<Mrt.Envelope?> = _gitEnvelopes.asStateFlow()

        val statusRequests = mutableListOf<GitStatusRequest>()
        val diffRequests = mutableListOf<GitDiffRequest>()
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
            statusRequests += GitStatusRequest(sessionId, requestId)
            return requestId
        }

        override suspend fun requestGitDiff(sessionId: String, path: String): String {
            counter += 1
            val requestId = "git-diff-$counter"
            diffRequests += GitDiffRequest(sessionId, path, requestId)
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

        data class GitStatusRequest(val sessionId: String, val requestId: String)
        data class GitDiffRequest(val sessionId: String, val path: String, val requestId: String)
    }
}
