package com.mrt.app.features.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.mrt.app.core.storage.ConnectionMode
import com.mrt.app.core.network.ConnectionState
import com.mrt.app.designsystem.components.GHBanner
import com.mrt.app.designsystem.components.GHBannerTone
import com.mrt.app.designsystem.components.GHButton
import com.mrt.app.designsystem.components.GHButtonStyle
import com.mrt.app.designsystem.components.GHCard
import com.mrt.app.designsystem.components.GHInput
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHSpacing
import com.mrt.app.designsystem.theme.GHType
import mrt.Mrt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConnectionSettings(
    mode: ConnectionMode,
    host: String,
    portText: String,
    nodeUrl: String,
    authToken: String,
    managedDevices: List<Mrt.DeviceInfo>,
    connectionState: ConnectionState,
    validationMessage: String?,
    didSave: Boolean,
    onModeChange: (ConnectionMode) -> Unit,
    onHostChange: (String) -> Unit,
    onPortChange: (String) -> Unit,
    onNodeUrlChange: (String) -> Unit,
    onAuthTokenChange: (String) -> Unit,
    onSave: () -> Unit,
    onConnectDevice: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    GHCard(modifier = modifier) {
        Column(verticalArrangement = Arrangement.spacedBy(GHSpacing.Md)) {
            Text("Connection Mode", style = GHType.BodySm, color = GHColors.TextSecondary)
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                val options = listOf(ConnectionMode.DIRECT to "Direct LAN", ConnectionMode.MANAGED to "Managed")
                options.forEachIndexed { index, option ->
                    SegmentedButton(
                        selected = mode == option.first,
                        onClick = { onModeChange(option.first) },
                        shape = androidx.compose.material3.SegmentedButtonDefaults.itemShape(index, options.size),
                    ) {
                        Text(option.second)
                    }
                }
            }

            if (mode == ConnectionMode.DIRECT) {
                GHInput(
                    value = host,
                    onValueChange = onHostChange,
                    placeholder = "192.168.1.25",
                    singleLine = true,
                )
                GHInput(
                    value = portText,
                    onValueChange = onPortChange,
                    placeholder = "9876",
                    singleLine = true,
                )
            } else {
                GHInput(
                    value = nodeUrl,
                    onValueChange = onNodeUrlChange,
                    placeholder = "wss://relay.example.com/ws",
                    singleLine = true,
                )
                GHInput(
                    value = authToken,
                    onValueChange = onAuthTokenChange,
                    placeholder = "mrt_ak_...",
                    singleLine = true,
                )
            }

            when {
                validationMessage != null -> GHBanner(
                    title = "Validation",
                    message = validationMessage,
                    tone = GHBannerTone.Warning,
                )
                didSave -> GHBanner(
                    title = "Saved",
                    message = "Connection preferences updated.",
                    tone = GHBannerTone.Success,
                )
            }

            if (mode == ConnectionMode.MANAGED) {
                when {
                    connectionState == ConnectionState.CONNECTING -> GHBanner(
                        title = "Connecting",
                        message = "Registering this phone with the Connection Node...",
                        tone = GHBannerTone.Info,
                    )
                    managedDevices.isEmpty() -> GHBanner(
                        title = "No agents yet",
                        message = "Save your Connection Node settings to load online desktop agents.",
                        tone = GHBannerTone.Neutral,
                    )
                    else -> Column(verticalArrangement = Arrangement.spacedBy(GHSpacing.Sm)) {
                        Text("Available Agents", style = GHType.BodySm, color = GHColors.TextSecondary)
                        managedDevices.forEach { device ->
                            GHCard(backgroundColor = GHColors.BgTertiary) {
                                Row(horizontalArrangement = Arrangement.spacedBy(GHSpacing.Sm)) {
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            text = device.displayName.ifBlank { device.deviceId },
                                            style = GHType.BodySm,
                                            color = GHColors.TextPrimary,
                                        )
                                        Text(
                                            text = device.deviceId,
                                            style = GHType.Caption,
                                            color = GHColors.TextSecondary,
                                        )
                                    }
                                    GHButton(
                                        text = "Connect",
                                        onClick = { onConnectDevice(device.deviceId) },
                                        style = GHButtonStyle.Secondary,
                                        modifier = Modifier.padding(top = GHSpacing.Xs),
                                    )
                                }
                            }
                        }
                    }
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(GHSpacing.Sm)) {
                GHButton(text = "Save Settings", onClick = onSave, style = GHButtonStyle.Primary)
            }
        }
    }
}
