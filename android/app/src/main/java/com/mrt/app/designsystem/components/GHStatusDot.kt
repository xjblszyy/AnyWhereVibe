package com.mrt.app.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.mrt.app.designsystem.theme.GHColors

enum class GHStatus {
    Online,
    Pending,
    Error,
    Offline,
}

@Composable
fun GHStatusDot(
    status: GHStatus,
    modifier: Modifier = Modifier,
) {
    val color = when (status) {
        GHStatus.Online -> GHColors.AccentGreen
        GHStatus.Pending -> GHColors.AccentYellow
        GHStatus.Error -> GHColors.AccentRed
        GHStatus.Offline -> GHColors.TextTertiary
    }

    Box(
        modifier = modifier
            .size(8.dp)
            .clip(CircleShape)
            .background(color),
    )
}
