package com.mrt.app.features.placeholders

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.mrt.app.designsystem.components.GHBadge
import com.mrt.app.designsystem.components.GHBanner
import com.mrt.app.designsystem.components.GHBannerTone
import com.mrt.app.designsystem.components.GHCard
import com.mrt.app.designsystem.components.GHCodeBlock
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHSpacing
import com.mrt.app.designsystem.theme.GHType

@Composable
fun FilesPlaceholderScreen(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(GHSpacing.Lg),
        verticalArrangement = Arrangement.spacedBy(GHSpacing.Lg),
    ) {
        androidx.compose.material3.Text("Files", style = GHType.TitleLg, color = GHColors.TextPrimary)
        GHBanner(
            title = "File browser pending",
            message = "The file browser remains intentionally out of scope for this feature slice.",
            tone = GHBannerTone.Info,
        )
        GHCard {
            androidx.compose.foundation.layout.Row(horizontalArrangement = Arrangement.spacedBy(GHSpacing.Sm)) {
                GHBadge(text = "android/", color = GHColors.AccentBlue)
                GHBadge(text = "ios/", color = GHColors.AccentPurple)
                GHBadge(text = "proto/", color = GHColors.AccentOrange)
            }
            GHCodeBlock(
                code = """
                    app/
                      src/main/java/com/mrt/app/features/
                      src/main/java/com/mrt/app/core/
                """.trimIndent(),
            )
        }
    }
}
