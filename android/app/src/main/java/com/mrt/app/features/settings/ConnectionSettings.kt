package com.mrt.app.features.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.mrt.app.core.storage.ConnectionMode
import com.mrt.app.designsystem.components.GHBanner
import com.mrt.app.designsystem.components.GHBannerTone
import com.mrt.app.designsystem.components.GHButton
import com.mrt.app.designsystem.components.GHButtonStyle
import com.mrt.app.designsystem.components.GHCard
import com.mrt.app.designsystem.components.GHInput
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHSpacing
import com.mrt.app.designsystem.theme.GHType

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConnectionSettings(
    mode: ConnectionMode,
    host: String,
    portText: String,
    validationMessage: String?,
    didSave: Boolean,
    onModeChange: (ConnectionMode) -> Unit,
    onHostChange: (String) -> Unit,
    onPortChange: (String) -> Unit,
    onSave: () -> Unit,
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

            Row(horizontalArrangement = Arrangement.spacedBy(GHSpacing.Sm)) {
                GHButton(text = "Save Settings", onClick = onSave, style = GHButtonStyle.Primary)
            }
        }
    }
}
