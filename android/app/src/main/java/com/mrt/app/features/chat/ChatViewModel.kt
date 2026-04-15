package com.mrt.app.features.chat

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.mrt.app.core.models.ChatMessage
import com.mrt.app.core.network.ConnectionManaging
import com.mrt.app.core.network.ConnectionState
import com.mrt.app.core.storage.ConnectionMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import mrt.Mrt

class ChatViewModel(
    private val connectionManager: ConnectionManaging,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
    private val nowMs: () -> Long = { System.currentTimeMillis() },
) {
    data class FeatureChatMessage(
        val id: String,
        val sessionId: String?,
        val content: String,
        val isComplete: Boolean,
        val role: Role,
        val timestampMs: Long,
        val order: Long,
    ) {
        enum class Role {
            USER,
            ASSISTANT,
            SYSTEM,
        }
    }

    private data class ConnectionConfiguration(
        val host: String,
        val port: Int,
        val mode: ConnectionMode,
    )

    var messages by mutableStateOf<List<FeatureChatMessage>>(emptyList())
        private set
    var inputText by mutableStateOf("")
    var connectionState by mutableStateOf(connectionManager.state.value)
    var pendingApproval by mutableStateOf<Mrt.ApprovalRequest?>(connectionManager.pendingApproval.value)
        private set
    private var activeSessionIdState by mutableStateOf<String?>(null)
    var activeSessionId: String?
        get() = activeSessionIdState
        set(value) {
            activeSessionIdState = value
            rebuildMessages()
        }

    private var localMessages: List<FeatureChatMessage> = emptyList()
    private var remoteMessages: List<ChatMessage> = connectionManager.messages.value
    private val remoteMessageOrders = linkedMapOf<String, Long>()
    private var nextOrder = 0L
    private var lastConnectionConfiguration: ConnectionConfiguration? = null

    init {
        scope.launch(context = Dispatchers.Unconfined, start = CoroutineStart.UNDISPATCHED) {
            connectionManager.state.collectLatest { state ->
                connectionState = state
            }
        }
        scope.launch(context = Dispatchers.Unconfined, start = CoroutineStart.UNDISPATCHED) {
            connectionManager.messages.collectLatest { messages ->
                remoteMessages = messages
                cacheRemoteMessageOrdering(messages)
                rebuildMessages()
            }
        }
        scope.launch(context = Dispatchers.Unconfined, start = CoroutineStart.UNDISPATCHED) {
            connectionManager.pendingApproval.collectLatest { approval ->
                pendingApproval = approval
                if (approval != null) {
                    connectionState = ConnectionState.SHOWING_APPROVAL
                } else if (connectionState == ConnectionState.SHOWING_APPROVAL) {
                    connectionState = ConnectionState.CONNECTED
                }
            }
        }
        rebuildMessages()
    }

    var isLoading: Boolean
        get() = connectionState == ConnectionState.LOADING
        set(value) {
            if (value) {
                connectionState = ConnectionState.LOADING
            } else if (connectionState == ConnectionState.LOADING) {
                connectionState = ConnectionState.CONNECTED
            }
        }

    val canSendPrompt: Boolean
        get() = !isLoading && activeSessionId != null && inputText.trim().isNotEmpty()

    val inputAssistiveMessage: String?
        get() = if (activeSessionId == null) {
            "Select or create a session to start chatting"
        } else {
            null
        }

    val sendButtonLabel: String
        get() = if (isLoading) "Sending" else "Send"

    val lastMessageSignature: String
        get() = messages.lastOrNull()?.let { "${it.id}:${it.content.length}:${it.isComplete}" } ?: "empty"

    suspend fun connectIfNeeded(host: String, port: Int, mode: ConnectionMode) {
        val configuration = ConnectionConfiguration(
            host = host.trim(),
            port = port,
            mode = mode,
        )
        val currentState = connectionManager.state.value
        val canRetryCurrentConfiguration =
            currentState == ConnectionState.DISCONNECTED || currentState == ConnectionState.RECONNECTING

        if (configuration == lastConnectionConfiguration && !canRetryCurrentConfiguration) {
            return
        }
        lastConnectionConfiguration = configuration
        if (mode != ConnectionMode.DIRECT) {
            connectionManager.disconnect()
            connectionState = connectionManager.state.value
            return
        }

        try {
            connectionManager.connect(host = configuration.host, port = configuration.port)
        } catch (_: Throwable) {
            connectionState = connectionManager.state.value
        }
    }

    suspend fun sendPrompt() {
        val prompt = inputText.trim()
        val sessionId = activeSessionId
        if (prompt.isEmpty() || sessionId == null) {
            return
        }

        localMessages = localMessages + FeatureChatMessage(
            id = "local-${nextOrder + 1}",
            sessionId = sessionId,
            content = prompt,
            isComplete = true,
            role = FeatureChatMessage.Role.USER,
            timestampMs = nowMs(),
            order = nextOrder(),
        )
        rebuildMessages()

        inputText = ""
        connectionState = ConnectionState.LOADING

        try {
            connectionManager.sendPrompt(prompt = prompt, sessionId = sessionId)
        } catch (_: Throwable) {
            localMessages = localMessages + FeatureChatMessage(
                id = "local-${nextOrder + 1}",
                sessionId = sessionId,
                content = "Unable to send prompt right now.",
                isComplete = true,
                role = FeatureChatMessage.Role.SYSTEM,
                timestampMs = nowMs(),
                order = nextOrder(),
            )
            rebuildMessages()
            connectionState = connectionManager.state.value
        }
    }

    suspend fun respondToApproval(approved: Boolean) {
        val approvalId = pendingApproval?.approvalId ?: return
        try {
            connectionManager.respondToApproval(approvalId = approvalId, approved = approved)
            pendingApproval = null
            if (connectionState == ConnectionState.SHOWING_APPROVAL) {
                connectionState = ConnectionState.CONNECTED
            }
        } catch (_: Throwable) {
        }
    }

    private fun rebuildMessages() {
        val mappedRemote = remoteMessages.map { message ->
            FeatureChatMessage(
                id = message.id.toString(),
                sessionId = message.sessionId,
                content = message.content,
                isComplete = message.isComplete,
                role = when (message.role) {
                    ChatMessage.Role.ASSISTANT -> FeatureChatMessage.Role.ASSISTANT
                    ChatMessage.Role.SYSTEM -> FeatureChatMessage.Role.SYSTEM
                },
                timestampMs = remoteMessageOrders[message.id.toString()] ?: nowMs(),
                order = remoteMessageOrders[message.id.toString()] ?: 0L,
            )
        }
        messages = (localMessages + mappedRemote)
            .filter(::isVisibleInActiveThread)
            .sortedWith(compareBy<FeatureChatMessage> { it.order }.thenBy { it.timestampMs })
    }

    private fun isVisibleInActiveThread(message: FeatureChatMessage): Boolean {
        if (message.sessionId == activeSessionId) {
            return true
        }
        return message.sessionId == null && message.role == FeatureChatMessage.Role.SYSTEM
    }

    private fun cacheRemoteMessageOrdering(messages: List<ChatMessage>) {
        messages.forEach { message ->
            val key = message.id.toString()
            if (remoteMessageOrders[key] == null) {
                remoteMessageOrders[key] = nextOrder()
            }
        }
    }

    private fun nextOrder(): Long {
        nextOrder += 1
        return nextOrder
    }
}
