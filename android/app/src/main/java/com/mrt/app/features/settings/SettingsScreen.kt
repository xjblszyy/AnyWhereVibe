package com.mrt.app.features.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.mrt.app.core.storage.ConnectionMode
import com.mrt.app.core.storage.PreferenceSnapshot
import com.mrt.app.core.storage.Preferences
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHSpacing
import com.mrt.app.designsystem.theme.GHType
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

@Composable
fun SettingsScreen(
    preferences: Preferences,
    modifier: Modifier = Modifier,
) {
    val snapshot by produceState(initialValue = PreferenceSnapshot()) {
        preferences.snapshot.collectLatest { value = it }
    }
    val scope = remember { CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate) }

    var mode by remember(snapshot.connectionConfigurationSignature) { mutableStateOf(snapshot.connectionMode) }
    var host by remember(snapshot.connectionConfigurationSignature) { mutableStateOf(snapshot.directHost) }
    var portText by remember(snapshot.connectionConfigurationSignature) { mutableStateOf(snapshot.directPort.toString()) }
    var didSave by remember(snapshot.connectionConfigurationSignature) { mutableStateOf(false) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(GHColors.BgPrimary)
            .padding(GHSpacing.Xl),
        verticalArrangement = Arrangement.spacedBy(GHSpacing.Lg),
    ) {
        androidx.compose.material3.Text(
            text = "Settings",
            style = GHType.TitleLg,
            color = GHColors.TextPrimary,
        )

        ConnectionSettings(
            mode = mode,
            host = host,
            portText = portText,
            validationMessage = validationMessage(mode, host, portText),
            didSave = didSave,
            onModeChange = {
                mode = it
                didSave = false
            },
            onHostChange = {
                host = it
                didSave = false
            },
            onPortChange = {
                portText = it
                didSave = false
            },
            onSave = {
                if (validationMessage(mode, host, portText) != null) {
                    didSave = false
                    return@ConnectionSettings
                }
                scope.launch {
                    preferences.setConnectionMode(mode)
                    preferences.setDirectHost(host.trim())
                    preferences.setDirectPort(portText.toInt())
                    didSave = true
                }
            },
        )
    }
}

private fun validationMessage(mode: ConnectionMode, host: String, portText: String): String? {
    if (mode != ConnectionMode.DIRECT) {
        return null
    }
    if (host.trim().isEmpty()) {
        return "Host is required for direct LAN mode."
    }
    val port = portText.toIntOrNull()
    if (port == null || port !in 1..65_535) {
        return "Port must be a number between 1 and 65535."
    }
    return null
}
