package com.mrt.app.core.storage

import org.junit.Assert.assertEquals
import org.junit.Test

class PreferencesSnapshotTest {
    @Test
    fun managedSignatureIncludesNodeUrlAndAuthToken() {
        val snapshot = PreferenceSnapshot(
            directHost = "127.0.0.1",
            directPort = 9876,
            connectionMode = ConnectionMode.MANAGED,
            nodeUrl = "wss://relay.example.com/ws",
            authToken = "mrt_ak_example1234567890",
            managedTargetDeviceId = "agent-1",
            managedTargetDeviceName = "Office Mac",
        )

        assertEquals(
            "MANAGED|127.0.0.1|9876|wss://relay.example.com/ws|mrt_ak_example1234567890|agent-1|Office Mac",
            snapshot.connectionConfigurationSignature,
        )
    }
}
