package com.mrt.app.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.mrt.app.designsystem.theme.GHType
import com.mrt.app.designsystem.theme.GHSpacing

@Composable
fun GHBadge(
    text: String,
    color: Color,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .background(color.copy(alpha = 0.15f), RoundedCornerShape(999.dp))
            .padding(horizontal = GHSpacing.Sm, vertical = GHSpacing.Xs / 2),
    ) {
        Text(
            text = text,
            color = color,
            style = GHType.Caption,
            fontWeight = FontWeight.Medium,
        )
    }
}
