package com.mrt.app.features.placeholders

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.mrt.app.designsystem.components.GHBanner
import com.mrt.app.designsystem.components.GHBannerTone
import com.mrt.app.designsystem.components.GHDiffKind
import com.mrt.app.designsystem.components.GHDiffLine
import com.mrt.app.designsystem.components.GHDiffView
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHSpacing
import com.mrt.app.designsystem.theme.GHType

@Composable
fun GitPlaceholderScreen(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(GHSpacing.Lg),
        verticalArrangement = Arrangement.spacedBy(GHSpacing.Lg),
    ) {
        androidx.compose.material3.Text("Git", style = GHType.TitleLg, color = GHColors.TextPrimary)
        GHBanner(
            title = "Git surface pending",
            message = "Git actions and diff navigation are still placeholders in this stage.",
            tone = GHBannerTone.Warning,
        )
        GHDiffView(
            title = "feature-layer.patch",
            lines = listOf(
                GHDiffLine(GHDiffKind.Context, "android/app/src/main/java/com/mrt/app/features/git"),
                GHDiffLine(GHDiffKind.Added, "Placeholder only for Task 8 parity"),
            ),
        )
    }
}
