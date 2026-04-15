package com.mrt.app.designsystem.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHRadii
import com.mrt.app.designsystem.theme.GHSpacing
import com.mrt.app.designsystem.theme.GHType

enum class GHBannerTone {
    Info,
    Success,
    Warning,
    Error,
    Neutral,
}

@Composable
fun GHBanner(
    title: String,
    message: String,
    modifier: Modifier = Modifier,
    tone: GHBannerTone = GHBannerTone.Info,
) {
    val accentColor = when (tone) {
        GHBannerTone.Info -> GHColors.AccentBlue
        GHBannerTone.Success -> GHColors.AccentGreen
        GHBannerTone.Warning -> GHColors.AccentYellow
        GHBannerTone.Error -> GHColors.AccentRed
        GHBannerTone.Neutral -> GHColors.TextSecondary
    }
    val icon = when (tone) {
        GHBannerTone.Info -> Icons.Outlined.Info
        GHBannerTone.Success -> Icons.Outlined.CheckCircle
        GHBannerTone.Warning -> Icons.Outlined.WarningAmber
        GHBannerTone.Error -> Icons.Outlined.ErrorOutline
        GHBannerTone.Neutral -> Icons.Outlined.Info
    }

    Surface(
        modifier = modifier.fillMaxWidth(),
        color = GHColors.BgSecondary,
        shape = androidx.compose.foundation.shape.RoundedCornerShape(GHRadii.Md),
        border = BorderStroke(1.dp, accentColor.copy(alpha = 0.45f)),
    ) {
        Row(
            modifier = Modifier.padding(GHSpacing.Md),
            horizontalArrangement = Arrangement.spacedBy(GHSpacing.Md),
        ) {
            BannerIcon(icon = icon, tint = accentColor)
            Column(verticalArrangement = Arrangement.spacedBy(GHSpacing.Xs)) {
                Text(text = title, style = GHType.BodySm, color = GHColors.TextPrimary)
                Text(text = message, style = GHType.BodySm, color = GHColors.TextSecondary)
            }
        }
    }
}

@Composable
private fun BannerIcon(
    icon: ImageVector,
    tint: Color,
) {
    Icon(
        imageVector = icon,
        contentDescription = null,
        tint = tint,
    )
}
