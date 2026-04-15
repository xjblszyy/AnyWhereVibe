package com.mrt.app.features.chat

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.mrt.app.designsystem.components.GHBadge
import com.mrt.app.designsystem.components.GHButton
import com.mrt.app.designsystem.components.GHButtonStyle
import com.mrt.app.designsystem.components.GHCodeBlock
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHRadii
import com.mrt.app.designsystem.theme.GHSpacing
import com.mrt.app.designsystem.theme.GHType
import mrt.Mrt

@Composable
fun ApprovalBanner(
    request: Mrt.ApprovalRequest,
    onApprove: () -> Unit,
    onReject: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = GHColors.BgSecondary,
        shape = androidx.compose.foundation.shape.RoundedCornerShape(GHRadii.Lg),
        border = BorderStroke(1.dp, GHColors.AccentYellow.copy(alpha = 0.45f)),
    ) {
        Column(
            modifier = Modifier.padding(GHSpacing.Lg),
            verticalArrangement = Arrangement.spacedBy(GHSpacing.Md),
        ) {
            Row {
                Text(
                    text = "Permission Required",
                    style = GHType.BodySm,
                    color = GHColors.AccentYellow,
                    fontWeight = FontWeight.SemiBold,
                )
                androidx.compose.foundation.layout.Spacer(modifier = Modifier.weight(1f))
                GHBadge(text = request.approvalType.displayName, color = GHColors.AccentYellow)
            }
            Text(
                text = request.description,
                style = GHType.BodySm,
                color = GHColors.TextSecondary,
            )
            if (request.command.isNotEmpty()) {
                GHCodeBlock(code = request.command)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(GHSpacing.Sm)) {
                GHButton(text = "Reject", onClick = onReject, style = GHButtonStyle.Danger)
                GHButton(text = "Approve", onClick = onApprove, style = GHButtonStyle.Primary)
            }
        }
    }
}

private val Mrt.ApprovalType.displayName: String
    get() = when (this) {
        Mrt.ApprovalType.FILE_WRITE -> "File Write"
        Mrt.ApprovalType.SHELL_COMMAND -> "Shell Command"
        Mrt.ApprovalType.NETWORK_ACCESS -> "Network"
        Mrt.ApprovalType.APPROVAL_TYPE_UNSPECIFIED,
        Mrt.ApprovalType.UNRECOGNIZED,
        -> "Approval"
    }
