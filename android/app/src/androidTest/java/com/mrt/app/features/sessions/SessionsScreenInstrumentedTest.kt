package com.mrt.app.features.sessions

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
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
class SessionsScreenInstrumentedTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun disconnectedRemoteSessionsShowAgentRequiredBanner() {
        val connectionManager = FakeSessionConnectionManager()
        val viewModel = SessionViewModel(connectionManager = connectionManager)

        composeRule.setContent {
            MRTTheme(darkTheme = true) {
                SessionsScreen(
                    viewModel = viewModel,
                    connectionState = ConnectionState.DISCONNECTED,
                )
            }
        }

        composeRule.onNodeWithText("Agent required").assertIsDisplayed()
        composeRule.onNodeWithText("Create").assertIsDisplayed()
    }

    @Test
    fun localSessionsScreenCreatesAndShowsNewSession() {
        val viewModel = SessionViewModel()

        composeRule.setContent {
            MRTTheme(darkTheme = true) {
                SessionsScreen(
                    viewModel = viewModel,
                    connectionState = ConnectionState.CONNECTED,
                )
            }
        }

        composeRule.onNodeWithText("Name").performTextInput("Daily")
        composeRule.onNodeWithText("Create").performClick()

        composeRule.onNodeWithText("Daily").assertIsDisplayed()
    }

    private class FakeSessionConnectionManager : ConnectionManaging {
        private val _state = MutableStateFlow(ConnectionState.DISCONNECTED)
        override val state: StateFlow<ConnectionState> = _state.asStateFlow()

        private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
        override val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

        private val _pendingApproval = MutableStateFlow<Mrt.ApprovalRequest?>(null)
        override val pendingApproval: StateFlow<Mrt.ApprovalRequest?> = _pendingApproval.asStateFlow()

        private val _sessions = MutableStateFlow<List<SessionModel>>(emptyList())
        override val sessions: StateFlow<List<SessionModel>> = _sessions.asStateFlow()

        override suspend fun connect(host: String, port: Int) = Unit
        override fun disconnect() = Unit
        override suspend fun sendPrompt(prompt: String, sessionId: String) = Unit
        override suspend fun respondToApproval(approvalId: String, approved: Boolean) = Unit
        override suspend fun cancelTask(sessionId: String) = Unit
        override suspend fun switchSession(sessionId: String) = Unit
        override suspend fun createSession(name: String, workingDirectory: String) = Unit
    }
}
