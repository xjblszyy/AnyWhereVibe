package com.mrt.app.designsystem.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val GhDarkColorScheme = darkColorScheme(
    primary = GHColors.AccentBlue,
    onPrimary = GHColors.TextPrimary,
    secondary = GHColors.AccentGreen,
    onSecondary = GHColors.TextPrimary,
    tertiary = GHColors.AccentPurple,
    background = GHColors.BgPrimary,
    onBackground = GHColors.TextPrimary,
    surface = GHColors.BgSecondary,
    onSurface = GHColors.TextPrimary,
    surfaceVariant = GHColors.BgTertiary,
    onSurfaceVariant = GHColors.TextSecondary,
    error = GHColors.AccentRed,
    onError = GHColors.TextPrimary,
    outline = GHColors.BorderDefault,
)

private val GhLightColorScheme = lightColorScheme(
    primary = GHColors.LightAccentBlue,
    onPrimary = GHColors.LightBgPrimary,
    secondary = GHColors.LightAccentGreen,
    onSecondary = GHColors.LightBgPrimary,
    tertiary = GHColors.AccentPurple,
    background = GHColors.LightBgPrimary,
    onBackground = GHColors.LightTextPrimary,
    surface = GHColors.LightBgSecondary,
    onSurface = GHColors.LightTextPrimary,
    surfaceVariant = GHColors.LightBgTertiary,
    onSurfaceVariant = GHColors.LightTextSecondary,
    error = GHColors.LightAccentRed,
    onError = GHColors.LightBgPrimary,
    outline = GHColors.LightBorderDefault,
)

@Composable
fun MRTTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) GhDarkColorScheme else GhLightColorScheme,
        typography = GHType.Material,
        content = content,
    )
}
