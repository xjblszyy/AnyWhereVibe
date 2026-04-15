package com.mrt.app.designsystem.components

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHType
import com.mrt.app.designsystem.theme.GHRadii

@Composable
fun GHInput(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    singleLine: Boolean = false,
    minLines: Int = 1,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.fillMaxWidth(),
        singleLine = singleLine,
        minLines = minLines,
        textStyle = GHType.Body,
        placeholder = {
            Text(text = placeholder, style = GHType.Body, color = GHColors.TextTertiary)
        },
        shape = RoundedCornerShape(GHRadii.Md),
        colors = OutlinedTextFieldDefaults.colors(
            focusedContainerColor = GHColors.BgSecondary,
            unfocusedContainerColor = GHColors.BgSecondary,
            disabledContainerColor = GHColors.BgSecondary,
            focusedBorderColor = GHColors.AccentBlue,
            unfocusedBorderColor = GHColors.BorderDefault,
            disabledBorderColor = GHColors.BorderMuted,
            focusedTextColor = GHColors.TextPrimary,
            unfocusedTextColor = GHColors.TextPrimary,
            cursorColor = GHColors.AccentBlue,
            focusedPlaceholderColor = GHColors.TextTertiary,
            unfocusedPlaceholderColor = GHColors.TextTertiary,
        ),
    )
}
