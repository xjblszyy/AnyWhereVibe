package com.mrt.app.network

import com.mrt.app.core.models.ChatMessage
import com.mrt.app.core.network.ConnectionState
import com.mrt.app.core.network.MessageDispatcher
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MessageDispatcherTest {
    @Test
    fun dispatcherAppendsStreamingCodexOutputIntoSingleMessage() {
        val dispatcher = MessageDispatcher()

        dispatcher.apply(makeCodexOutputEnvelope(content = "Hello ", complete = false))
        dispatcher.apply(makeCodexOutputEnvelope(content = "world", complete = true))

        assertEquals("Hello world", dispatcher.messages.last().content)
        assertTrue(dispatcher.messages.last().isComplete)
    }

    @Test
    fun dispatcherStoresApprovalAndUpdatesState() {
        val dispatcher = MessageDispatcher()

        dispatcher.apply(makeApprovalRequestEnvelope())

        assertEquals("approval-1", dispatcher.pendingApproval?.approvalId)
        assertEquals(ConnectionState.SHOWING_APPROVAL, dispatcher.state)
    }

    @Test
    fun dispatcherUpdatesSessionsFromSessionListEvent() {
        val dispatcher = MessageDispatcher()

        dispatcher.apply(makeSessionListEnvelope())

        assertEquals(listOf("session-1"), dispatcher.sessions.map { it.id })
        assertEquals("Main", dispatcher.sessions.first().name)
    }

    @Test
    fun dispatcherTurnsBusinessErrorsIntoSystemMessages() {
        val dispatcher = MessageDispatcher()

        dispatcher.apply(makeErrorEnvelope(message = "Agent is busy", fatal = false))

        assertEquals("Agent is busy", dispatcher.messages.last().content)
        assertEquals(ChatMessage.Role.SYSTEM, dispatcher.messages.last().role)
        assertEquals(ConnectionState.DISCONNECTED, dispatcher.state)
    }

    @Test
    fun dispatcherClearsLoadingStateAfterNonFatalError() {
        val dispatcher = MessageDispatcher()

        dispatcher.apply(makeRunningStatusEnvelope())
        assertEquals(ConnectionState.LOADING, dispatcher.state)

        dispatcher.apply(makeErrorEnvelope(message = "Busy", fatal = false))

        assertEquals(ConnectionState.CONNECTED, dispatcher.state)
    }
}
