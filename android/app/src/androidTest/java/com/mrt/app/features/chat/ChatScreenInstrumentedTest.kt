package com.mrt.app.features.chat

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.mrt.app.core.models.ChatMessage
import com.mrt.app.core.models.SessionModel
import com.mrt.app.core.network.ConnectionManaging
import com.mrt.app.core.network.ConnectionState
import com.mrt.app.designsystem.theme.MRTTheme
import com.mrt.app.features.sessions.SessionViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import mrt.Mrt
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ChatScreenInstrumentedTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun emptyChatShowsNoMessagesBanner() {
        val connectionManager = FakeChatConnectionManager()
        val chatViewModel = ChatViewModel(connectionManager = connectionManager)
        val sessionViewModel = SessionViewModel(
            initialSessions = listOf(session("session-1", "Main Session")),
        )
        chatViewModel.activeSessionId = sessionViewModel.activeSessionId

        composeRule.setContent {
            MRTTheme(darkTheme = true) {
                ChatScreen(
                    viewModel = chatViewModel,
                    sessionViewModel = sessionViewModel,
                )
            }
        }

        composeRule.onNodeWithText("No messages yet").assertIsDisplayed()
        composeRule.onNodeWithText("Send a prompt once your LAN settings are configured.").assertIsDisplayed()
    }

    @Test
    fun sendButtonShowsOptimisticLocalMessage() {
        val connectionManager = FakeChatConnectionManager()
        val chatViewModel = ChatViewModel(connectionManager = connectionManager)
        val sessionViewModel = SessionViewModel(
            initialSessions = listOf(session("session-1", "Main Session")),
        )
        chatViewModel.activeSessionId = sessionViewModel.activeSessionId

        composeRule.setContent {
            MRTTheme(darkTheme = true) {
                ChatScreen(
                    viewModel = chatViewModel,
                    sessionViewModel = sessionViewModel,
                )
            }
        }

        composeRule.onNodeWithTag("chatComposerInput").performTextInput("Ship it")
        composeRule.onNodeWithTag("chatSendButton").performClick()

        composeRule.runOnIdle {
            assertEquals("session-1", chatViewModel.activeSessionId)
            assertEquals(true, chatViewModel.messages.any { it.content == "Ship it" })
            assertEquals(listOf("Ship it"), connectionManager.sentPrompts.map { it.prompt })
        }
    }

    private fun session(id: String, name: String) = SessionModel(
        id = id,
        name = name,
        status = Mrt.TaskStatus.IDLE,
        createdAtMs = 1,
        lastActiveMs = 1,
        workingDirectory = "/tmp/$name",
    )

    private class FakeChatConnectionManager : ConnectionManaging {
        private val _state = MutableStateFlow(ConnectionState.CONNECTED)
        override val state: StateFlow<ConnectionState> = _state.asStateFlow()

        private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
        override val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

        private val _pendingApproval = MutableStateFlow<Mrt.ApprovalRequest?>(null)
        override val pendingApproval: StateFlow<Mrt.ApprovalRequest?> = _pendingApproval.asStateFlow()

        private val _sessions = MutableStateFlow<List<SessionModel>>(emptyList())
        override val sessions: StateFlow<List<SessionModel>> = _sessions.asStateFlow()

        val sentPrompts = mutableListOf<PromptCall>()

        override suspend fun connect(host: String, port: Int) = Unit
        override fun disconnect() = Unit
        override suspend fun sendPrompt(prompt: String, sessionId: String) {
            sentPrompts += PromptCall(prompt, sessionId)
        }
        override suspend fun respondToApproval(approvalId: String, approved: Boolean) = Unit
        override suspend fun cancelTask(sessionId: String) = Unit
        override suspend fun switchSession(sessionId: String) = Unit
        override suspend fun createSession(name: String, workingDirectory: String) = Unit

        data class PromptCall(val prompt: String, val sessionId: String)
    }
}
