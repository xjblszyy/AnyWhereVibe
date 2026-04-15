package com.mrt.app.designsystem.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHType

enum class GHButtonStyle {
    Primary,
    Secondary,
    Danger,
}

@Composable
fun GHButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    style: GHButtonStyle = GHButtonStyle.Primary,
    icon: ImageVector? = null,
    enabled: Boolean = true,
) {
    val backgroundColor = when (style) {
        GHButtonStyle.Primary -> GHColors.AccentBlue.copy(alpha = 0.15f)
        GHButtonStyle.Secondary -> GHColors.BgSecondary
        GHButtonStyle.Danger -> GHColors.AccentRed.copy(alpha = 0.15f)
    }
    val foregroundColor = when (style) {
        GHButtonStyle.Primary -> GHColors.AccentBlue
        GHButtonStyle.Secondary -> GHColors.TextSecondary
        GHButtonStyle.Danger -> GHColors.AccentRed
    }
    val border = if (style == GHButtonStyle.Secondary) {
        BorderStroke(1.dp, GHColors.BorderDefault)
    } else {
        null
    }

    Button(
        onClick = onClick,
        modifier = modifier.defaultMinSize(minHeight = 36.dp),
        enabled = enabled,
        shape = androidx.compose.foundation.shape.RoundedCornerShape(6.dp),
        border = border,
        colors = ButtonDefaults.buttonColors(
            containerColor = backgroundColor,
            contentColor = foregroundColor,
            disabledContainerColor = backgroundColor.copy(alpha = 0.4f),
            disabledContentColor = foregroundColor.copy(alpha = 0.5f),
        ),
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
        ) {
            if (icon != null) {
                Icon(imageVector = icon, contentDescription = null)
            }
            Text(
                text = text,
                style = GHType.BodySm,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(vertical = 2.dp),
            )
        }
    }
}
