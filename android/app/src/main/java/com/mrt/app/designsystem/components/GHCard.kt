package com.mrt.app.designsystem.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHRadii
import com.mrt.app.designsystem.theme.GHSpacing

@Composable
fun GHCard(
    modifier: Modifier = Modifier,
    backgroundColor: Color = GHColors.BgSecondary,
    content: @Composable ColumnScope.() -> Unit,
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = backgroundColor,
        shape = androidx.compose.foundation.shape.RoundedCornerShape(GHRadii.Lg),
        border = BorderStroke(1.dp, GHColors.BorderDefault),
    ) {
        Column(
            modifier = Modifier.padding(GHSpacing.Lg),
            content = content,
        )
    }
}
