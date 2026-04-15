package com.mrt.app.features.settings

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.mrt.app.core.network.ConnectionState
import com.mrt.app.core.storage.ConnectionMode
import com.mrt.app.designsystem.theme.MRTTheme
import mrt.Mrt
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ConnectionSettingsInstrumentedTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun managedModeRendersManagedInputsAndAvailableAgents() {
        composeRule.setContent {
            MRTTheme(darkTheme = true) {
                ConnectionSettings(
                    mode = ConnectionMode.MANAGED,
                    host = "",
                    portText = "",
                    nodeUrl = "wss://relay.example.com/ws",
                    authToken = "mrt_ak_example1234567890",
                    managedDevices = listOf(agent("agent-1", "Office Mac")),
                    connectionState = ConnectionState.CONNECTED,
                    validationMessage = null,
                    didSave = false,
                    onModeChange = {},
                    onHostChange = {},
                    onPortChange = {},
                    onNodeUrlChange = {},
                    onAuthTokenChange = {},
                    onSave = {},
                    onConnectDevice = {},
                )
            }
        }

        composeRule.onNodeWithText("wss://relay.example.com/ws").assertIsDisplayed()
        composeRule.onNodeWithText("mrt_ak_example1234567890").assertIsDisplayed()
        composeRule.onNodeWithText("Available Agents").assertIsDisplayed()
        composeRule.onNodeWithText("Office Mac").assertIsDisplayed()
        composeRule.onNodeWithText("agent-1").assertIsDisplayed()
        composeRule.onNodeWithText("Connect").assertIsDisplayed()
    }

    @Test
    fun connectButtonInvokesManagedDeviceCallback() {
        var selectedDeviceId: String? = null

        composeRule.setContent {
            MRTTheme(darkTheme = true) {
                ConnectionSettings(
                    mode = ConnectionMode.MANAGED,
                    host = "",
                    portText = "",
                    nodeUrl = "wss://relay.example.com/ws",
                    authToken = "mrt_ak_example1234567890",
                    managedDevices = listOf(agent("agent-1", "Office Mac")),
                    connectionState = ConnectionState.CONNECTED,
                    validationMessage = null,
                    didSave = false,
                    onModeChange = {},
                    onHostChange = {},
                    onPortChange = {},
                    onNodeUrlChange = {},
                    onAuthTokenChange = {},
                    onSave = {},
                    onConnectDevice = { selectedDeviceId = it },
                )
            }
        }

        composeRule.onNodeWithText("Connect").performClick()

        composeRule.runOnIdle {
            assertEquals("agent-1", selectedDeviceId)
        }
    }

    private fun agent(id: String, displayName: String): Mrt.DeviceInfo =
        Mrt.DeviceInfo.newBuilder()
            .setDeviceId(id)
            .setDisplayName(displayName)
            .setDeviceType(Mrt.DeviceType.AGENT)
            .setIsOnline(true)
            .build()
}
