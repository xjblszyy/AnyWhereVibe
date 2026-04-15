package com.mrt.app.features.chat

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHRadii
import com.mrt.app.designsystem.theme.GHSpacing
import com.mrt.app.designsystem.theme.GHType

@Composable
fun ThreadMessage(
    message: ChatViewModel.FeatureChatMessage,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = if (message.role == ChatViewModel.FeatureChatMessage.Role.USER) {
            Arrangement.End
        } else {
            Arrangement.Start
        },
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth(0.86f)
                .widthIn(min = 0.dp),
            color = backgroundColor(message.role),
            shape = androidx.compose.foundation.shape.RoundedCornerShape(GHRadii.Lg),
            border = BorderStroke(1.dp, borderColor(message.role)),
        ) {
            Column(
                modifier = Modifier.padding(GHSpacing.Md),
                verticalArrangement = Arrangement.spacedBy(GHSpacing.Sm),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        text = roleTitle(message.role),
                        style = GHType.BodySm,
                        color = roleAccent(message.role),
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = formatRelativeTimestamp(message.timestampMs),
                        style = GHType.Caption,
                        color = GHColors.TextTertiary,
                    )
                }
                if (message.role == ChatViewModel.FeatureChatMessage.Role.ASSISTANT) {
                    StreamingText(content = message.content, isStreaming = !message.isComplete)
                } else {
                    Text(
                        text = message.content,
                        style = GHType.Body,
                        color = GHColors.TextPrimary,
                    )
                }
            }
        }
    }
}

internal fun formatRelativeTimestamp(timestampMs: Long, nowMs: Long = System.currentTimeMillis()): String {
    val deltaSeconds = ((nowMs - timestampMs).coerceAtLeast(0L)) / 1_000L
    return when {
        deltaSeconds < 60L -> "${deltaSeconds}s ago"
        deltaSeconds < 3_600L -> "${deltaSeconds / 60L}m ago"
        deltaSeconds < 86_400L -> "${deltaSeconds / 3_600L}h ago"
        else -> "${deltaSeconds / 86_400L}d ago"
    }
}

private fun roleTitle(role: ChatViewModel.FeatureChatMessage.Role): String = when (role) {
    ChatViewModel.FeatureChatMessage.Role.ASSISTANT -> "Codex"
    ChatViewModel.FeatureChatMessage.Role.SYSTEM -> "System"
    ChatViewModel.FeatureChatMessage.Role.USER -> "You"
}

private fun roleAccent(role: ChatViewModel.FeatureChatMessage.Role): Color = when (role) {
    ChatViewModel.FeatureChatMessage.Role.ASSISTANT -> GHColors.AccentBlue
    ChatViewModel.FeatureChatMessage.Role.SYSTEM -> GHColors.AccentOrange
    ChatViewModel.FeatureChatMessage.Role.USER -> GHColors.TextPrimary
}

private fun backgroundColor(role: ChatViewModel.FeatureChatMessage.Role): Color = when (role) {
    ChatViewModel.FeatureChatMessage.Role.ASSISTANT -> GHColors.BgSecondary
    ChatViewModel.FeatureChatMessage.Role.SYSTEM -> GHColors.BgTertiary
    ChatViewModel.FeatureChatMessage.Role.USER -> GHColors.BgOverlay
}

private fun borderColor(role: ChatViewModel.FeatureChatMessage.Role): Color = when (role) {
    ChatViewModel.FeatureChatMessage.Role.USER -> GHColors.AccentBlue.copy(alpha = 0.35f)
    else -> GHColors.BorderDefault
}
