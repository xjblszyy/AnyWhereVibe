package com.mrt.app.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Badge
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHRadii
import com.mrt.app.designsystem.theme.GHSpacing
import com.mrt.app.designsystem.theme.GHType

data class GHTabItem(
    val key: String,
    val title: String,
    val icon: ImageVector,
    val badge: String? = null,
)

@Composable
fun GHTabBar(
    items: List<GHTabItem>,
    selectedKey: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(GHColors.BgSecondary)
            .padding(horizontal = GHSpacing.Md, vertical = GHSpacing.Sm),
        horizontalArrangement = Arrangement.spacedBy(GHSpacing.Sm),
    ) {
        items.forEach { item ->
            val selected = item.key == selectedKey
            Column(
                modifier = Modifier
                    .weight(1f)
                    .background(
                        color = if (selected) GHColors.BgTertiary else GHColors.BgSecondary,
                        shape = RoundedCornerShape(GHRadii.Md),
                    )
                    .clickable { onSelect(item.key) }
                    .padding(vertical = GHSpacing.Sm),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(GHSpacing.Xs),
            ) {
                Box(contentAlignment = Alignment.TopEnd) {
                    Icon(
                        imageVector = item.icon,
                        contentDescription = item.title,
                        tint = if (selected) GHColors.TextPrimary else GHColors.TextSecondary,
                        modifier = Modifier.size(18.dp),
                    )
                    if (item.badge != null) {
                        Badge(
                            modifier = Modifier.align(Alignment.TopEnd),
                            containerColor = GHColors.AccentRed,
                            contentColor = GHColors.TextPrimary,
                        ) {
                            Text(text = item.badge, style = GHType.CodeSm)
                        }
                    }
                }
                Text(
                    text = item.title,
                    style = GHType.Caption,
                    color = if (selected) GHColors.TextPrimary else GHColors.TextSecondary,
                    fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                )
            }
        }
    }
}
