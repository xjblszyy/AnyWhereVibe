package com.mrt.app.features.settings

import com.mrt.app.core.storage.ConnectionMode
import org.junit.Assert.assertEquals
import org.junit.Test

class SettingsValidationTest {
    @Test
    fun managedModeRequiresNodeUrl() {
        assertEquals(
            "Connection Node URL is required for managed mode.",
            connectionValidationMessage(
                mode = ConnectionMode.MANAGED,
                host = "127.0.0.1",
                portText = "9876",
                nodeUrl = "",
                authToken = "mrt_ak_example1234567890",
            ),
        )
    }

    @Test
    fun managedModeRequiresAuthToken() {
        assertEquals(
            "Auth token is required for managed mode.",
            connectionValidationMessage(
                mode = ConnectionMode.MANAGED,
                host = "127.0.0.1",
                portText = "9876",
                nodeUrl = "wss://relay.example.com/ws",
                authToken = "",
            ),
        )
    }
}
