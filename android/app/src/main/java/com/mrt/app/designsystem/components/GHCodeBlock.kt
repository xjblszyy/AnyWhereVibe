package com.mrt.app.designsystem.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHRadii
import com.mrt.app.designsystem.theme.GHSpacing
import com.mrt.app.designsystem.theme.GHType

@Composable
fun GHCodeBlock(
    code: String,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = GHColors.BgTertiary,
        shape = androidx.compose.foundation.shape.RoundedCornerShape(GHRadii.Sm),
        border = BorderStroke(1.dp, GHColors.BorderDefault),
    ) {
        Box(
            modifier = Modifier
                .horizontalScroll(rememberScrollState())
                .padding(GHSpacing.Md),
        ) {
            Text(
                text = code,
                style = GHType.Code,
                color = GHColors.TextPrimary,
            )
        }
    }
}
