package com.mrt.app.core.models

import java.util.UUID

data class ChatMessage(
    val id: UUID = UUID.randomUUID(),
    val sessionId: String?,
    val content: String,
    val isComplete: Boolean,
    val role: Role,
) {
    enum class Role {
        ASSISTANT,
        SYSTEM,
    }
}
