package com.mrt.app.designsystem.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

object GHType {
    private val sans = FontFamily.SansSerif
    private val mono = FontFamily.Monospace

    val TitleLg = TextStyle(
        fontFamily = sans,
        fontSize = 24.sp,
        fontWeight = FontWeight.Bold,
        lineHeight = 30.sp,
    )
    val Title = TextStyle(
        fontFamily = sans,
        fontSize = 17.sp,
        fontWeight = FontWeight.SemiBold,
        lineHeight = 24.sp,
    )
    val Body = TextStyle(
        fontFamily = sans,
        fontSize = 15.sp,
        fontWeight = FontWeight.Normal,
        lineHeight = 22.sp,
    )
    val BodySm = TextStyle(
        fontFamily = sans,
        fontSize = 13.sp,
        fontWeight = FontWeight.Normal,
        lineHeight = 18.sp,
    )
    val Caption = TextStyle(
        fontFamily = sans,
        fontSize = 12.sp,
        fontWeight = FontWeight.Normal,
        lineHeight = 16.sp,
    )
    val Code = TextStyle(
        fontFamily = mono,
        fontSize = 13.sp,
        fontWeight = FontWeight.Normal,
        lineHeight = 18.sp,
    )
    val CodeSm = TextStyle(
        fontFamily = mono,
        fontSize = 11.sp,
        fontWeight = FontWeight.Normal,
        lineHeight = 14.sp,
    )

    val Material = Typography(
        headlineSmall = TitleLg,
        titleMedium = Title,
        bodyLarge = Body,
        bodyMedium = BodySm,
        bodySmall = Caption,
        labelMedium = BodySm.copy(fontWeight = FontWeight.Medium),
        labelSmall = Caption.copy(fontWeight = FontWeight.Medium),
    )
}
