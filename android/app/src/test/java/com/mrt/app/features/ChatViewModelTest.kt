package com.mrt.app.features

import com.mrt.app.core.models.ChatMessage
import com.mrt.app.core.models.SessionModel
import com.mrt.app.core.network.ConnectionManaging
import com.mrt.app.core.network.ConnectionState
import com.mrt.app.core.storage.ConnectionMode
import com.mrt.app.features.chat.ChatViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import mrt.Mrt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ChatViewModelTest {
    @Test
    fun connectIfNeededRetriesWhenConfigurationChanges() = runTest {
        val connection = FakeConnectionManager()
        val viewModel = ChatViewModel(connectionManager = connection, scope = backgroundScope)

        viewModel.connectIfNeeded(host = "127.0.0.1", port = 9876, mode = ConnectionMode.DIRECT)
        viewModel.connectIfNeeded(host = "127.0.0.1", port = 9876, mode = ConnectionMode.DIRECT)
        viewModel.connectIfNeeded(host = "127.0.0.2", port = 9876, mode = ConnectionMode.DIRECT)

        assertEquals(listOf("127.0.0.1", "127.0.0.2"), connection.connectCalls.map { it.host })
    }

    @Test
    fun connectIfNeededRetriesSameConfigurationWhenDisconnectedOrReconnecting() = runTest {
        val connection = FakeConnectionManager()
        val viewModel = ChatViewModel(connectionManager = connection, scope = backgroundScope)

        viewModel.connectIfNeeded(host = "127.0.0.1", port = 9876, mode = ConnectionMode.DIRECT)
        connection.emitState(ConnectionState.DISCONNECTED)
        viewModel.connectIfNeeded(host = "127.0.0.1", port = 9876, mode = ConnectionMode.DIRECT)
        connection.emitState(ConnectionState.RECONNECTING)
        viewModel.connectIfNeeded(host = "127.0.0.1", port = 9876, mode = ConnectionMode.DIRECT)

        assertEquals(listOf("127.0.0.1", "127.0.0.1", "127.0.0.1"), connection.connectCalls.map { it.host })
    }

    @Test
    fun connectIfNeededLeavesManagedModeToDedicatedNodeFlow() = runTest {
        val connection = FakeConnectionManager()
        val viewModel = ChatViewModel(connectionManager = connection, scope = backgroundScope)

        viewModel.connectIfNeeded(host = "127.0.0.1", port = 9876, mode = ConnectionMode.DIRECT)
        viewModel.connectIfNeeded(host = "127.0.0.1", port = 9876, mode = ConnectionMode.MANAGED)

        assertEquals(1, connection.connectCalls.size)
        assertEquals(0, connection.disconnectCalls)
        assertEquals(ConnectionState.CONNECTED, viewModel.connectionState)
    }

    @Test
    fun switchingSessionsChangesVisibleThreadButKeepsGlobalSystemMessages() = runTest {
        val connection = FakeConnectionManager()
        val viewModel = ChatViewModel(connectionManager = connection, scope = backgroundScope)
        viewModel.activeSessionId = "session-1"

        connection.emitMessages(
            listOf(
                ChatMessage(sessionId = "session-1", content = "Session one", isComplete = true, role = ChatMessage.Role.ASSISTANT),
                ChatMessage(sessionId = "session-2", content = "Session two", isComplete = true, role = ChatMessage.Role.ASSISTANT),
                ChatMessage(sessionId = null, content = "Global system note", isComplete = true, role = ChatMessage.Role.SYSTEM),
            ),
        )
        advanceUntilIdle()

        assertEquals(listOf("Session one", "Global system note"), viewModel.messages.map { it.content })

        viewModel.activeSessionId = "session-2"

        assertEquals(listOf("Session two", "Global system note"), viewModel.messages.map { it.content })
    }

    @Test
    fun sendPromptCreatesUserMessageAndStartsLoading() = runTest {
        val connection = FakeConnectionManager()
        val viewModel = ChatViewModel(connectionManager = connection, scope = backgroundScope)

        viewModel.activeSessionId = "session-1"
        viewModel.inputText = "Ship it"
        viewModel.sendPrompt()
        advanceUntilIdle()

        assertEquals(ChatViewModel.FeatureChatMessage.Role.USER, viewModel.messages.first().role)
        assertTrue(viewModel.isLoading)
        assertEquals(listOf("Ship it"), connection.sentPrompts.map { it.prompt })
    }

    @Test
    fun sendPromptWithoutActiveSessionDoesNothing() = runTest {
        val connection = FakeConnectionManager()
        val viewModel = ChatViewModel(connectionManager = connection, scope = backgroundScope)

        viewModel.activeSessionId = null
        viewModel.inputText = "Ship it"

        viewModel.sendPrompt()
        advanceUntilIdle()

        assertTrue(connection.sentPrompts.isEmpty())
        assertTrue(viewModel.messages.isEmpty())
        assertFalse(viewModel.isLoading)
        assertEquals("Ship it", viewModel.inputText)
    }

    @Test
    fun promptComposerStateTracksSessionAndLoading() = runTest {
        val connection = FakeConnectionManager()
        val viewModel = ChatViewModel(connectionManager = connection, scope = backgroundScope)

        assertFalse(viewModel.canSendPrompt)
        assertEquals("Select or create a session to start chatting", viewModel.inputAssistiveMessage)

        viewModel.activeSessionId = "session-1"
        viewModel.inputText = "Ship it"

        assertTrue(viewModel.canSendPrompt)
        assertEquals(null, viewModel.inputAssistiveMessage)

        viewModel.isLoading = true

        assertFalse(viewModel.canSendPrompt)
        assertEquals("Sending", viewModel.sendButtonLabel)
    }

    @Test
    fun chatViewModelObservesConnectionManagerMessagesAndApprovals() = runTest {
        val connection = FakeConnectionManager()
        val viewModel = ChatViewModel(connectionManager = connection, scope = backgroundScope)
        viewModel.activeSessionId = "session-1"

        connection.emitState(ConnectionState.CONNECTING)
        advanceUntilIdle()
        assertEquals(ConnectionState.CONNECTING, viewModel.connectionState)

        connection.emitMessages(
            listOf(
                ChatMessage(sessionId = "session-1", content = "Hello ", isComplete = false, role = ChatMessage.Role.ASSISTANT),
                ChatMessage(sessionId = null, content = "System note", isComplete = true, role = ChatMessage.Role.SYSTEM),
            ),
        )
        advanceUntilIdle()

        assertEquals(2, viewModel.messages.size)
        assertEquals(ChatViewModel.FeatureChatMessage.Role.ASSISTANT, viewModel.messages[0].role)
        assertEquals(ChatViewModel.FeatureChatMessage.Role.SYSTEM, viewModel.messages[1].role)

        val approval = Mrt.ApprovalRequest.newBuilder()
            .setApprovalId("approval-1")
            .setSessionId("session-1")
            .setDescription("Write file")
            .setCommand("echo hi")
            .build()
        connection.emitApproval(approval)
        advanceUntilIdle()

        assertEquals("approval-1", viewModel.pendingApproval?.approvalId)
        assertEquals(ConnectionState.SHOWING_APPROVAL, viewModel.connectionState)

        viewModel.respondToApproval(true)
        advanceUntilIdle()

        assertEquals(1, connection.respondedApprovals.size)
        assertEquals("approval-1", connection.respondedApprovals.first().approvalId)
        assertTrue(connection.respondedApprovals.first().approved)
    }
}

internal class FakeConnectionManager : ConnectionManaging {
    private val _state = MutableStateFlow(ConnectionState.DISCONNECTED)
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

    val connectCalls = mutableListOf<ConnectCall>()
    val sentPrompts = mutableListOf<PromptCall>()
    val respondedApprovals = mutableListOf<ApprovalCall>()
    val switchedSessions = mutableListOf<String>()
    val createdSessions = mutableListOf<CreateSessionCall>()
    val cancelledSessions = mutableListOf<String>()
    val closedSessions = mutableListOf<String>()
    var disconnectCalls = 0

    override suspend fun connect(host: String, port: Int) {
        connectCalls += ConnectCall(host, port)
        _state.value = ConnectionState.CONNECTED
    }

    override fun disconnect() {
        disconnectCalls += 1
        _state.value = ConnectionState.DISCONNECTED
    }

    override suspend fun sendPrompt(prompt: String, sessionId: String) {
        sentPrompts += PromptCall(prompt, sessionId)
    }

    override suspend fun respondToApproval(approvalId: String, approved: Boolean) {
        respondedApprovals += ApprovalCall(approvalId, approved)
        _pendingApproval.value = null
    }

    override suspend fun cancelTask(sessionId: String) {
        cancelledSessions += sessionId
    }

    override suspend fun switchSession(sessionId: String) {
        switchedSessions += sessionId
    }

    override suspend fun createSession(name: String, workingDirectory: String) {
        createdSessions += CreateSessionCall(name, workingDirectory)
    }

    override suspend fun closeSession(sessionId: String) {
        closedSessions += sessionId
    }

    override suspend fun listDirectory(sessionId: String, path: String): String = "file-list"
    override suspend fun readFile(sessionId: String, path: String): String = "file-read"
    override suspend fun writeFile(sessionId: String, path: String, content: ByteArray): String = "file-write"
    override suspend fun createFile(sessionId: String, path: String): String = "file-create"
    override suspend fun createDirectory(sessionId: String, path: String): String = "dir-create"
    override suspend fun deletePath(sessionId: String, path: String, recursive: Boolean): String = "file-delete"
    override suspend fun renamePath(sessionId: String, fromPath: String, toPath: String): String = "file-rename"

    override suspend fun requestGitStatus(sessionId: String): String = "git-status"

    override suspend fun requestGitDiff(sessionId: String, path: String): String = "git-diff"

    fun emitState(value: ConnectionState) {
        _state.value = value
    }

    fun emitMessages(value: List<ChatMessage>) {
        _messages.value = value
    }

    fun emitApproval(value: Mrt.ApprovalRequest?) {
        _pendingApproval.value = value
    }

    fun emitSessions(value: List<SessionModel>) {
        _sessions.value = value
    }

    data class ConnectCall(val host: String, val port: Int)
    data class PromptCall(val prompt: String, val sessionId: String)
    data class ApprovalCall(val approvalId: String, val approved: Boolean)
    data class CreateSessionCall(val name: String, val workingDirectory: String)
}
