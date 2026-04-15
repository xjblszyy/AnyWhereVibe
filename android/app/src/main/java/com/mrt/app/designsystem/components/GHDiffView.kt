package com.mrt.app.designsystem.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
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

enum class GHDiffKind {
    Added,
    Removed,
    Context,
}

data class GHDiffLine(
    val kind: GHDiffKind,
    val content: String,
)

@Composable
fun GHDiffView(
    title: String,
    lines: List<GHDiffLine>,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = GHColors.BgSecondary,
        shape = androidx.compose.foundation.shape.RoundedCornerShape(GHRadii.Lg),
        border = BorderStroke(1.dp, GHColors.BorderDefault),
    ) {
        Column(
            modifier = Modifier.padding(GHSpacing.Lg),
            verticalArrangement = Arrangement.spacedBy(GHSpacing.Sm),
        ) {
            Text(
                text = title,
                style = GHType.BodySm,
                color = GHColors.TextPrimary,
                fontWeight = FontWeight.SemiBold,
            )
            lines.forEach { line ->
                val prefix = when (line.kind) {
                    GHDiffKind.Added -> "+"
                    GHDiffKind.Removed -> "-"
                    GHDiffKind.Context -> " "
                }
                val color = when (line.kind) {
                    GHDiffKind.Added -> GHColors.AccentGreen
                    GHDiffKind.Removed -> GHColors.AccentRed
                    GHDiffKind.Context -> GHColors.TextSecondary
                }
                val background = when (line.kind) {
                    GHDiffKind.Added -> GHColors.AccentGreen.copy(alpha = 0.08f)
                    GHDiffKind.Removed -> GHColors.AccentRed.copy(alpha = 0.08f)
                    GHDiffKind.Context -> Color.Transparent
                }
                Text(
                    text = "$prefix ${line.content}",
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = GHSpacing.Sm)
                        .background(background, androidx.compose.foundation.shape.RoundedCornerShape(GHRadii.Sm))
                        .padding(horizontal = GHSpacing.Sm, vertical = GHSpacing.Xs),
                    style = GHType.Code,
                    color = color,
                )
            }
        }
    }
}
