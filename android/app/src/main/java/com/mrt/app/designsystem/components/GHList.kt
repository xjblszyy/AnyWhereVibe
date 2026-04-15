package com.mrt.app.designsystem.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHRadii
import com.mrt.app.designsystem.theme.GHSpacing
import com.mrt.app.designsystem.theme.GHType

data class GHListItem(
    val id: String,
    val title: String,
    val subtitle: String,
    val status: GHStatus = GHStatus.Offline,
    val badgeText: String? = null,
)

@Composable
fun GHList(
    items: List<GHListItem>,
    modifier: Modifier = Modifier,
    onItemClick: (GHListItem) -> Unit = {},
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = GHColors.BgSecondary,
        shape = androidx.compose.foundation.shape.RoundedCornerShape(GHRadii.Lg),
        border = BorderStroke(1.dp, GHColors.BorderDefault),
    ) {
        Column {
            items.forEachIndexed { index, item ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onItemClick(item) }
                        .padding(GHSpacing.Lg),
                    horizontalArrangement = Arrangement.spacedBy(GHSpacing.Md),
                ) {
                    GHStatusDot(status = item.status)
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(GHSpacing.Xs)) {
                        Text(
                            text = item.title,
                            style = GHType.BodySm,
                            color = GHColors.TextPrimary,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            text = item.subtitle,
                            style = GHType.BodySm,
                            color = GHColors.TextSecondary,
                        )
                    }
                    if (item.badgeText != null) {
                        GHBadge(text = item.badgeText, color = GHColors.AccentBlue)
                    }
                }
                if (index != items.lastIndex) {
                    HorizontalDivider(color = GHColors.BorderMuted)
                }
            }
        }
    }
}
