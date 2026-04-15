package com.mrt.app.features

import com.mrt.app.core.models.SessionModel
import com.mrt.app.core.network.ConnectionState
import com.mrt.app.features.sessions.SessionViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import mrt.Mrt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SessionViewModelTest {
    @Test
    fun sessionViewModelDoesNotCreateRemoteSessionWhileConnecting() = runTest {
        val connection = FakeConnectionManager()
        connection.emitState(ConnectionState.CONNECTING)
        val viewModel = SessionViewModel(connectionManager = connection, scope = backgroundScope)

        viewModel.createSession(named = "Daily")
        advanceUntilIdle()

        assertTrue(connection.createdSessions.isEmpty())
        assertTrue(viewModel.sessions.isEmpty())
    }

    @Test
    fun sessionViewModelCreatesRemoteSessionWhenConnected() = runTest {
        val connection = FakeConnectionManager()
        connection.emitState(ConnectionState.CONNECTED)
        val viewModel = SessionViewModel(connectionManager = connection, scope = backgroundScope)

        viewModel.createSession(named = "Daily")
        advanceUntilIdle()

        assertEquals(listOf("Daily"), connection.createdSessions.map { it.name })
    }

    @Test
    fun sessionViewModelAcceptsAuthoritativeSessionUpdatesAndPreservesSelection() = runTest {
        val connection = FakeConnectionManager()
        val viewModel = SessionViewModel(connectionManager = connection, scope = backgroundScope)

        connection.emitSessions(
            listOf(
                SessionModel(
                    id = "session-1",
                    name = "Main",
                    status = Mrt.TaskStatus.RUNNING,
                    createdAtMs = 1,
                    lastActiveMs = 2,
                    workingDirectory = "/tmp/main",
                ),
                SessionModel(
                    id = "session-2",
                    name = "Docs",
                    status = Mrt.TaskStatus.IDLE,
                    createdAtMs = 3,
                    lastActiveMs = 4,
                    workingDirectory = "/tmp/docs",
                ),
            ),
        )
        advanceUntilIdle()

        assertEquals(listOf("session-1", "session-2"), viewModel.sessions.map { it.id })
        assertEquals("session-1", viewModel.activeSessionId)

        viewModel.selectSession("session-2")
        advanceUntilIdle()

        connection.emitSessions(
            listOf(
                SessionModel(
                    id = "session-2",
                    name = "Docs",
                    status = Mrt.TaskStatus.RUNNING,
                    createdAtMs = 3,
                    lastActiveMs = 5,
                    workingDirectory = "/tmp/docs",
                ),
            ),
        )
        advanceUntilIdle()

        assertEquals(listOf("session-2"), viewModel.sessions.map { it.id })
        assertEquals("session-2", viewModel.activeSessionId)
        assertEquals(listOf("session-2"), connection.switchedSessions)
    }

    @Test
    fun sessionViewModelClosesRemoteSessionWhenConnected() = runTest {
        val connection = FakeConnectionManager()
        connection.emitState(ConnectionState.CONNECTED)
        connection.emitSessions(
            listOf(
                SessionModel(
                    id = "session-1",
                    name = "Main",
                    status = Mrt.TaskStatus.IDLE,
                    createdAtMs = 1,
                    lastActiveMs = 2,
                    workingDirectory = "/tmp/main",
                ),
            ),
        )
        val viewModel = SessionViewModel(
            connectionManager = connection,
            scope = backgroundScope,
        )

        viewModel.closeSession("session-1")
        advanceUntilIdle()

        assertEquals(listOf("session-1"), connection.closedSessions)
    }

    @Test
    fun sessionViewModelClosesLocalSessionAndReselectsRemainingItem() = runTest {
        val first = SessionModel(
            id = "session-1",
            name = "Main",
            status = Mrt.TaskStatus.IDLE,
            createdAtMs = 1,
            lastActiveMs = 2,
            workingDirectory = "/tmp/main",
        )
        val second = SessionModel(
            id = "session-2",
            name = "Docs",
            status = Mrt.TaskStatus.IDLE,
            createdAtMs = 3,
            lastActiveMs = 4,
            workingDirectory = "/tmp/docs",
        )
        val viewModel = SessionViewModel(initialSessions = listOf(first, second))

        viewModel.selectSession("session-2")
        viewModel.closeSession("session-2")

        assertEquals(listOf("session-1"), viewModel.sessions.map { it.id })
        assertEquals("session-1", viewModel.activeSessionId)
    }
}
