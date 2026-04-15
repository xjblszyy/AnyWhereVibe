package com.mrt.app.features.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.mrt.app.core.network.ConnectionState
import com.mrt.app.designsystem.components.GHStatus
import com.mrt.app.designsystem.components.GHStatusDot
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHSpacing
import com.mrt.app.designsystem.theme.GHType

@Composable
fun ConnectionStatusBar(
    state: ConnectionState,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(GHColors.BgSecondary)
            .padding(horizontal = GHSpacing.Lg, vertical = GHSpacing.Sm),
        horizontalArrangement = Arrangement.spacedBy(GHSpacing.Sm),
    ) {
        GHStatusDot(status = dotStatus(state))
        Text(
            text = statusText(state),
            style = GHType.Caption,
            color = GHColors.TextSecondary,
        )
    }
}

private fun statusText(state: ConnectionState): String = when (state) {
    ConnectionState.DISCONNECTED -> "Disconnected"
    ConnectionState.CONNECTING -> "Connecting to LAN agent"
    ConnectionState.CONNECTED -> "Connected"
    ConnectionState.LOADING -> "Waiting for response"
    ConnectionState.SHOWING_APPROVAL -> "Approval required"
    ConnectionState.RECONNECTING -> "Reconnecting"
}

private fun dotStatus(state: ConnectionState): GHStatus = when (state) {
    ConnectionState.CONNECTED -> GHStatus.Online
    ConnectionState.CONNECTING,
    ConnectionState.LOADING,
    ConnectionState.SHOWING_APPROVAL,
    ConnectionState.RECONNECTING,
    -> GHStatus.Pending

    ConnectionState.DISCONNECTED -> GHStatus.Offline
}
