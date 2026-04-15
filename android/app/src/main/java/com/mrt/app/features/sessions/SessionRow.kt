package com.mrt.app.features.sessions

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.mrt.app.core.models.SessionModel
import com.mrt.app.designsystem.components.GHBadge
import com.mrt.app.designsystem.components.GHButton
import com.mrt.app.designsystem.components.GHButtonStyle
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHRadii
import com.mrt.app.designsystem.theme.GHSpacing
import com.mrt.app.designsystem.theme.GHType
import mrt.Mrt

@Composable
fun SessionRow(
    session: SessionModel,
    isActive: Boolean,
    onSelect: () -> Unit,
    onCancel: (() -> Unit)? = null,
    onClose: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .clickable { onSelect() },
        color = if (isActive) GHColors.BgTertiary else GHColors.BgSecondary,
        shape = androidx.compose.foundation.shape.RoundedCornerShape(GHRadii.Md),
        border = BorderStroke(
            1.dp,
            if (isActive) GHColors.AccentBlue.copy(alpha = 0.35f) else GHColors.BorderDefault,
        ),
    ) {
        Row(
            modifier = Modifier.padding(GHSpacing.Md),
            horizontalArrangement = Arrangement.spacedBy(GHSpacing.Md),
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(GHSpacing.Xs)) {
                Text(
                    text = session.name,
                    style = GHType.BodySm,
                    color = GHColors.TextPrimary,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = session.workingDirectory,
                    style = GHType.Caption,
                    color = GHColors.TextSecondary,
                    maxLines = 1,
                )
            }
            Column(verticalArrangement = Arrangement.spacedBy(GHSpacing.Xs)) {
                GHBadge(
                    text = session.status.displayName,
                    color = if (isActive) GHColors.AccentBlue else GHColors.TextTertiary,
                )
                if (onCancel != null && session.isCancellable) {
                    GHButton(
                        text = "Cancel",
                        onClick = onCancel,
                        style = GHButtonStyle.Danger,
                        modifier = Modifier.testTag("cancelTask:${session.id}"),
                    )
                }
                if (onClose != null && session.isClosable) {
                    GHButton(
                        text = "Close",
                        onClick = onClose,
                        style = GHButtonStyle.Danger,
                        modifier = Modifier.testTag("closeSession:${session.id}"),
                    )
                }
            }
        }
    }
}

private val Mrt.TaskStatus.displayName: String
    get() = when (this) {
        Mrt.TaskStatus.IDLE -> "Idle"
        Mrt.TaskStatus.RUNNING -> "Running"
        Mrt.TaskStatus.WAITING_APPROVAL -> "Needs Approval"
        Mrt.TaskStatus.COMPLETED -> "Completed"
        Mrt.TaskStatus.ERROR -> "Error"
        Mrt.TaskStatus.CANCELLED -> "Cancelled"
        Mrt.TaskStatus.TASK_STATUS_UNSPECIFIED,
        Mrt.TaskStatus.UNRECOGNIZED,
        -> "Unknown"
    }

private val SessionModel.isClosable: Boolean
    get() = status != Mrt.TaskStatus.RUNNING && status != Mrt.TaskStatus.WAITING_APPROVAL

private val SessionModel.isCancellable: Boolean
    get() = status == Mrt.TaskStatus.RUNNING || status == Mrt.TaskStatus.WAITING_APPROVAL
