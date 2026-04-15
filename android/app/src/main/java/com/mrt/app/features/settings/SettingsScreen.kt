package com.mrt.app.features.settings

import android.os.Build
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.mrt.app.core.network.ConnectionManager
import com.mrt.app.core.network.ConnectionState
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
import mrt.Mrt

@Composable
fun SettingsScreen(
    preferences: Preferences,
    connectionManager: ConnectionManager,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val snapshot by produceState(initialValue = PreferenceSnapshot()) {
        preferences.snapshot.collectLatest { value = it }
    }
    val managedDevices by produceState(initialValue = emptyList<Mrt.DeviceInfo>()) {
        connectionManager.devices.collectLatest { value = it }
    }
    val connectionState by produceState(initialValue = connectionManager.state.value) {
        connectionManager.state.collectLatest { value = it }
    }
    val scope = remember { CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate) }

    var mode by remember(snapshot.connectionConfigurationSignature) { mutableStateOf(snapshot.connectionMode) }
    var host by remember(snapshot.connectionConfigurationSignature) { mutableStateOf(snapshot.directHost) }
    var portText by remember(snapshot.connectionConfigurationSignature) { mutableStateOf(snapshot.directPort.toString()) }
    var nodeUrl by remember(snapshot.connectionConfigurationSignature) { mutableStateOf(snapshot.nodeUrl) }
    var authToken by remember(snapshot.connectionConfigurationSignature) { mutableStateOf(snapshot.authToken) }
    var didSave by remember(snapshot.connectionConfigurationSignature) { mutableStateOf(false) }

    LaunchedEffect(mode, connectionState, nodeUrl, authToken) {
        if (
            mode == ConnectionMode.MANAGED &&
            connectionState == ConnectionState.CONNECTED &&
            managedDevices.isEmpty() &&
            nodeUrl.isNotBlank() &&
            authToken.isNotBlank()
        ) {
            connectionManager.requestDeviceList()
        }
    }

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
            nodeUrl = nodeUrl,
            authToken = authToken,
            managedDevices = managedDevices.filter { it.deviceType == Mrt.DeviceType.AGENT },
            connectionState = connectionState,
            validationMessage = connectionValidationMessage(mode, host, portText, nodeUrl, authToken),
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
            onNodeUrlChange = {
                nodeUrl = it
                didSave = false
            },
            onAuthTokenChange = {
                authToken = it
                didSave = false
            },
            onSave = {
                if (connectionValidationMessage(mode, host, portText, nodeUrl, authToken) != null) {
                    didSave = false
                    return@ConnectionSettings
                }
                scope.launch {
                    preferences.setConnectionMode(mode)
                    preferences.setDirectHost(host.trim())
                    preferences.setDirectPort(portText.toInt())
                    preferences.setNodeUrl(nodeUrl.trim())
                    preferences.setAuthToken(authToken.trim())
                    if (mode == ConnectionMode.MANAGED) {
                        connectionManager.connectManaged(
                            nodeUrl = nodeUrl.trim(),
                            authToken = authToken.trim(),
                            deviceId = managedPhoneDeviceId(context),
                            displayName = managedPhoneDisplayName(),
                            targetDeviceId = snapshot.managedTargetDeviceId.ifBlank { null },
                        )
                    }
                    didSave = true
                }
            },
            onConnectDevice = { deviceId ->
                scope.launch {
                    val deviceName = managedDevices.firstOrNull { it.deviceId == deviceId }?.displayName
                        ?: deviceId
                    preferences.setManagedTargetDevice(deviceId, deviceName)
                    connectionManager.connectToDevice(deviceId)
                }
            },
        )
    }
}

internal fun connectionValidationMessage(
    mode: ConnectionMode,
    host: String,
    portText: String,
    nodeUrl: String,
    authToken: String,
): String? {
    return when (mode) {
        ConnectionMode.DIRECT -> {
            if (host.trim().isEmpty()) {
                "Host is required for direct LAN mode."
            } else {
                val port = portText.toIntOrNull()
                if (port == null || port !in 1..65_535) {
                    "Port must be a number between 1 and 65535."
                } else {
                    null
                }
            }
        }
        ConnectionMode.MANAGED -> when {
            nodeUrl.trim().isEmpty() -> "Connection Node URL is required for managed mode."
            authToken.trim().isEmpty() -> "Auth token is required for managed mode."
            else -> null
        }
    }
}

private fun managedPhoneDeviceId(context: android.content.Context): String {
    val androidId = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
    return if (androidId.isNullOrBlank()) {
        "android-phone"
    } else {
        "android-$androidId"
    }
}

private fun managedPhoneDisplayName(): String {
    val manufacturer = Build.MANUFACTURER.orEmpty().trim()
    val model = Build.MODEL.orEmpty().trim()
    return listOf(manufacturer, model)
        .filter { it.isNotBlank() }
        .joinToString(" ")
        .ifBlank { "Android Phone" }
}
