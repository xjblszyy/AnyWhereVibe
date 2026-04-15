package com.mrt.app.core.network

import com.mrt.app.core.models.ChatMessage
import com.mrt.app.core.models.SessionModel
import mrt.Mrt

class MessageDispatcher {
    var messages: List<ChatMessage> = emptyList()
        private set
    var sessions: List<SessionModel> = emptyList()
        private set
    var pendingApproval: Mrt.ApprovalRequest? = null
        private set
    var state: ConnectionState = ConnectionState.DISCONNECTED
        private set
    var agentInfo: Mrt.AgentInfo? = null
        private set

    fun apply(envelope: Mrt.Envelope) {
        if (envelope.payloadCase != Mrt.Envelope.PayloadCase.EVENT) {
            return
        }

        when (envelope.event.evtCase) {
            Mrt.AgentEvent.EvtCase.CODEX_OUTPUT -> applyCodexOutput(envelope.event.codexOutput)
            Mrt.AgentEvent.EvtCase.APPROVAL_REQUEST -> {
                pendingApproval = envelope.event.approvalRequest
                state = ConnectionState.SHOWING_APPROVAL
            }
            Mrt.AgentEvent.EvtCase.STATUS_UPDATE -> applyStatus(envelope.event.statusUpdate.status)
            Mrt.AgentEvent.EvtCase.SESSION_LIST ->
                sessions = envelope.event.sessionList.sessionsList.map(SessionModel::fromProto)

            Mrt.AgentEvent.EvtCase.AGENT_INFO -> {
                agentInfo = envelope.event.agentInfo
                state = ConnectionState.CONNECTED
            }
            Mrt.AgentEvent.EvtCase.ERROR -> {
                val error = envelope.event.error
                messages = messages + ChatMessage(
                    sessionId = null,
                    content = error.message,
                    isComplete = true,
                    role = ChatMessage.Role.SYSTEM,
                )
                state = if (error.fatal) {
                    ConnectionState.RECONNECTING
                } else if (state != ConnectionState.DISCONNECTED) {
                    ConnectionState.CONNECTED
                } else {
                    ConnectionState.DISCONNECTED
                }
            }
            Mrt.AgentEvent.EvtCase.EVT_NOT_SET -> Unit
            null -> Unit
        }
    }

    fun clearPendingApproval() {
        pendingApproval = null
        if (state == ConnectionState.SHOWING_APPROVAL) {
            state = ConnectionState.CONNECTED
        }
    }

    private fun applyCodexOutput(output: Mrt.CodexOutput) {
        val current = messages.lastOrNull()
        if (
            current != null &&
            current.sessionId == output.sessionId &&
            current.role == ChatMessage.Role.ASSISTANT &&
            !current.isComplete
        ) {
            messages = messages.dropLast(1) + current.copy(
                content = current.content + output.content,
                isComplete = output.isComplete,
            )
            return
        }

        messages = messages + ChatMessage(
            sessionId = output.sessionId,
            content = output.content,
            isComplete = output.isComplete,
            role = ChatMessage.Role.ASSISTANT,
        )
    }

    private fun applyStatus(status: Mrt.TaskStatus) {
        state = when (status) {
            Mrt.TaskStatus.RUNNING -> ConnectionState.LOADING
            Mrt.TaskStatus.WAITING_APPROVAL -> ConnectionState.SHOWING_APPROVAL
            Mrt.TaskStatus.COMPLETED,
            Mrt.TaskStatus.IDLE,
            Mrt.TaskStatus.CANCELLED,
            Mrt.TaskStatus.ERROR,
            Mrt.TaskStatus.TASK_STATUS_UNSPECIFIED,
            Mrt.TaskStatus.UNRECOGNIZED,
            -> ConnectionState.CONNECTED
        }
    }
}
