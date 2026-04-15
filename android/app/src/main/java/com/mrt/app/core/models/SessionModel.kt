package com.mrt.app.core.models

import mrt.Mrt

data class SessionModel(
    val id: String,
    val name: String,
    val status: Mrt.TaskStatus,
    val createdAtMs: Long,
    val lastActiveMs: Long,
    val workingDirectory: String,
) {
    companion object {
        fun fromProto(session: Mrt.SessionInfo): SessionModel =
            SessionModel(
                id = session.sessionId,
                name = session.name,
                status = session.status,
                createdAtMs = session.createdAtMs,
                lastActiveMs = session.lastActiveMs,
                workingDirectory = session.workingDir,
            )
    }
}
