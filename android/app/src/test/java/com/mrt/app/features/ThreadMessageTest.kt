package com.mrt.app.features

import com.mrt.app.features.chat.formatRelativeTimestamp
import org.junit.Assert.assertEquals
import org.junit.Test

class ThreadMessageTest {
    @Test
    fun formatRelativeTimestampUsesSecondsForRecentMessages() {
        assertEquals("45s ago", formatRelativeTimestamp(timestampMs = 1_000, nowMs = 46_000))
    }

    @Test
    fun formatRelativeTimestampUsesHoursForOlderMessages() {
        assertEquals("2h ago", formatRelativeTimestamp(timestampMs = 0, nowMs = 7_200_000))
    }
}
