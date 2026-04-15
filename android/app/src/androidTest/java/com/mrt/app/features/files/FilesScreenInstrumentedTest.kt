package com.mrt.app.features.files

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
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
class FilesScreenInstrumentedTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun filesScreenBrowsesDirectoryAndSavesTextFile() {
        val connectionManager = FakeFilesConnectionManager()
        val viewModel = FilesViewModel(connectionManager = connectionManager)

        composeRule.setContent {
            MRTTheme(darkTheme = true) {
                FilesScreen(viewModel = viewModel)
            }
        }

        composeRule.runOnIdle {
            viewModel.updateContext(ConnectionState.CONNECTED, "session-1")
            viewModel.setVisible(true)
        }
        composeRule.waitUntil { connectionManager.listRequests.isNotEmpty() }
        composeRule.runOnIdle {
            connectionManager.emitDirListing(
                sessionId = "session-1",
                requestId = connectionManager.listRequests.last().requestId,
                entries = listOf("Sources" to true),
            )
        }
        composeRule.onNodeWithTag("filesEntry:Sources").performClick()
        composeRule.waitUntil { connectionManager.listRequests.size >= 2 }
        composeRule.runOnIdle {
            connectionManager.emitDirListing(
                sessionId = "session-1",
                requestId = connectionManager.listRequests.last().requestId,
                entries = listOf("Sources/App.kt" to false),
            )
        }
        composeRule.onNodeWithTag("filesEntry:Sources/App.kt").performClick()
        composeRule.waitUntil { connectionManager.readRequests.isNotEmpty() }
        composeRule.runOnIdle {
            connectionManager.emitFileContent(
                sessionId = "session-1",
                requestId = connectionManager.readRequests.last().requestId,
                path = "Sources/App.kt",
                content = "old\n",
            )
        }
        composeRule.onNodeWithTag("filesEditor").performTextClearance()
        composeRule.onNodeWithTag("filesEditor").performTextInput("new\n")
        composeRule.onNodeWithText("Save").performClick()
        composeRule.waitUntil { connectionManager.writeRequests.isNotEmpty() }
        composeRule.runOnIdle {
            connectionManager.emitWriteAck(
                sessionId = "session-1",
                requestId = connectionManager.writeRequests.last().requestId,
                path = "Sources/App.kt",
            )
        }
        composeRule.waitUntil { connectionManager.listRequests.size >= 3 }
        composeRule.runOnIdle {
            connectionManager.emitDirListing(
                sessionId = "session-1",
                requestId = connectionManager.listRequests.last().requestId,
                entries = listOf("Sources/App.kt" to false),
            )
        }

        composeRule.onNodeWithTag("filesPreview").fetchSemanticsNode()
    }

    private class FakeFilesConnectionManager : ConnectionManaging {
        private val _state = MutableStateFlow(ConnectionState.CONNECTED)
        override val state: StateFlow<ConnectionState> = _state.asStateFlow()

        private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
        override val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

        private val _pendingApproval = MutableStateFlow<Mrt.ApprovalRequest?>(null)
        override val pendingApproval: StateFlow<Mrt.ApprovalRequest?> = _pendingApproval.asStateFlow()

        private val _sessions = MutableStateFlow<List<SessionModel>>(emptyList())
        override val sessions: StateFlow<List<SessionModel>> = _sessions.asStateFlow()

        private val _fileEnvelopes = MutableStateFlow<Mrt.Envelope?>(null)
        override val fileEnvelopes: StateFlow<Mrt.Envelope?> = _fileEnvelopes.asStateFlow()

        private val _gitEnvelopes = MutableStateFlow<Mrt.Envelope?>(null)
        override val gitEnvelopes: StateFlow<Mrt.Envelope?> = _gitEnvelopes.asStateFlow()

        val listRequests = mutableListOf<Request>()
        val readRequests = mutableListOf<Request>()
        val writeRequests = mutableListOf<Request>()
        private var counter = 0

        override suspend fun connect(host: String, port: Int) = Unit
        override fun disconnect() = Unit
        override suspend fun sendPrompt(prompt: String, sessionId: String) = Unit
        override suspend fun respondToApproval(approvalId: String, approved: Boolean) = Unit
        override suspend fun cancelTask(sessionId: String) = Unit
        override suspend fun switchSession(sessionId: String) = Unit
        override suspend fun createSession(name: String, workingDirectory: String) = Unit
        override suspend fun closeSession(sessionId: String) = Unit
        override suspend fun requestGitStatus(sessionId: String): String = "git-status"
        override suspend fun requestGitDiff(sessionId: String, path: String): String = "git-diff"
        override suspend fun createFile(sessionId: String, path: String): String = nextId("create-file")
        override suspend fun createDirectory(sessionId: String, path: String): String = nextId("create-dir")
        override suspend fun deletePath(sessionId: String, path: String, recursive: Boolean): String = nextId("delete")
        override suspend fun renamePath(sessionId: String, fromPath: String, toPath: String): String = nextId("rename")

        override suspend fun listDirectory(sessionId: String, path: String): String {
            val id = nextId("list")
            listRequests += Request(sessionId, path, id)
            return id
        }

        override suspend fun readFile(sessionId: String, path: String): String {
            val id = nextId("read")
            readRequests += Request(sessionId, path, id)
            return id
        }

        override suspend fun writeFile(sessionId: String, path: String, content: ByteArray): String {
            val id = nextId("write")
            writeRequests += Request(sessionId, path, id)
            return id
        }

        fun emitDirListing(sessionId: String, requestId: String, entries: List<Pair<String, Boolean>>) {
            _fileEnvelopes.value = Mrt.Envelope.newBuilder()
                .setRequestId(requestId)
                .setFileResult(
                    Mrt.FileResult.newBuilder()
                        .setSessionId(sessionId)
                        .setDirListing(
                            Mrt.DirListing.newBuilder()
                                .addAllEntries(
                                    entries.map { (path, isDir) ->
                                        val name = path.split("/").last()
                                        Mrt.FileEntry.newBuilder()
                                            .setName(name)
                                            .setPath(path)
                                            .setIsDir(isDir)
                                            .setSize(0)
                                            .setModifiedMs(1)
                                            .build()
                                    },
                                )
                                .build(),
                        )
                        .build(),
                )
                .build()
        }

        fun emitFileContent(sessionId: String, requestId: String, path: String, content: String) {
            _fileEnvelopes.value = Mrt.Envelope.newBuilder()
                .setRequestId(requestId)
                .setFileResult(
                    Mrt.FileResult.newBuilder()
                        .setSessionId(sessionId)
                        .setFileContent(
                            Mrt.FileContent.newBuilder()
                                .setPath(path)
                                .setContent(com.google.protobuf.ByteString.copyFromUtf8(content))
                                .setMimeType("text/plain")
                                .build(),
                        )
                        .build(),
                )
                .build()
        }

        fun emitWriteAck(sessionId: String, requestId: String, path: String) {
            _fileEnvelopes.value = Mrt.Envelope.newBuilder()
                .setRequestId(requestId)
                .setFileResult(
                    Mrt.FileResult.newBuilder()
                        .setSessionId(sessionId)
                        .setWriteAck(Mrt.FileWriteAck.newBuilder().setPath(path).setSuccess(true).build())
                        .build(),
                )
                .build()
        }

        private fun nextId(prefix: String): String {
            counter += 1
            return "$prefix-$counter"
        }

        data class Request(val sessionId: String, val path: String, val requestId: String)
    }
}
