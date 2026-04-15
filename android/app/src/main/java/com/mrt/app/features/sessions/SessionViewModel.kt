package com.mrt.app.features.sessions

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.mrt.app.core.models.SessionModel
import com.mrt.app.core.network.ConnectionManaging
import com.mrt.app.core.network.ConnectionState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import mrt.Mrt
import java.util.UUID

class SessionViewModel(
    private val connectionManager: ConnectionManaging? = null,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
    initialSessions: List<SessionModel> = connectionManager?.sessions?.value ?: emptyList(),
) {
    var sessions by mutableStateOf(initialSessions)
        private set
    var activeSessionId by mutableStateOf(initialSessions.firstOrNull()?.id)
        private set

    init {
        connectionManager?.let { manager ->
            scope.launch(context = Dispatchers.Unconfined, start = CoroutineStart.UNDISPATCHED) {
                manager.sessions.collectLatest { authoritativeSessions ->
                    applyAuthoritativeSessions(authoritativeSessions)
                }
            }
        }
    }

    fun selectSession(id: String): Boolean {
        if (sessions.none { it.id == id }) {
            return false
        }

        activeSessionId = id
        connectionManager?.let { manager ->
            scope.launch(start = CoroutineStart.UNDISPATCHED) {
                try {
                    manager.switchSession(sessionId = id)
                } catch (_: Throwable) {
                }
            }
        }
        return true
    }

    fun canCreateSession(connectionState: ConnectionState? = null): Boolean {
        val manager = connectionManager ?: return true
        return (connectionState ?: manager.state.value) == ConnectionState.CONNECTED
    }

    fun createSession(named: String) {
        val trimmedName = named.trim()
        if (trimmedName.isEmpty()) {
            return
        }

        connectionManager?.let { manager ->
            if (!canCreateSession()) {
                return
            }
            scope.launch(start = CoroutineStart.UNDISPATCHED) {
                try {
                    manager.createSession(name = trimmedName, workingDirectory = "")
                } catch (_: Throwable) {
                }
            }
            return
        }

        val timestamp = System.currentTimeMillis()
        val session = SessionModel(
            id = UUID.randomUUID().toString(),
            name = trimmedName,
            status = Mrt.TaskStatus.IDLE,
            createdAtMs = timestamp,
            lastActiveMs = timestamp,
            workingDirectory = "/tmp/${trimmedName.replace(" ", "-").lowercase()}",
        )
        sessions = listOf(session) + sessions
        activeSessionId = session.id
    }

    fun closeSession(id: String) {
        connectionManager?.let { manager ->
            if (sessions.none { it.id == id }) {
                return
            }
            scope.launch(start = CoroutineStart.UNDISPATCHED) {
                try {
                    manager.closeSession(sessionId = id)
                } catch (_: Throwable) {
                }
            }
            return
        }

        sessions = sessions.filterNot { it.id == id }
        activeSessionId = when {
            activeSessionId != id -> activeSessionId
            else -> sessions.firstOrNull()?.id
        }
    }

    fun cancelTask(id: String) {
        connectionManager?.let { manager ->
            if (sessions.none { it.id == id }) {
                return
            }
            scope.launch(start = CoroutineStart.UNDISPATCHED) {
                try {
                    manager.cancelTask(sessionId = id)
                } catch (_: Throwable) {
                }
            }
            return
        }

        val updatedAt = System.currentTimeMillis()
        sessions = sessions.map { session ->
            if (session.id != id) {
                session
            } else {
                session.copy(
                    status = Mrt.TaskStatus.CANCELLED,
                    lastActiveMs = updatedAt,
                )
            }
        }
    }

    private fun applyAuthoritativeSessions(authoritativeSessions: List<SessionModel>) {
        val previousSelection = activeSessionId
        sessions = authoritativeSessions
        activeSessionId = when {
            previousSelection != null && authoritativeSessions.any { it.id == previousSelection } -> previousSelection
            else -> authoritativeSessions.firstOrNull()?.id
        }
    }
}
