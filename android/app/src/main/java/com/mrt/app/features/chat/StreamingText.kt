package com.mrt.app.features.chat

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.mrt.app.designsystem.components.GHCodeBlock
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHSpacing
import com.mrt.app.designsystem.theme.GHType

@Composable
fun StreamingText(
    content: String,
    isStreaming: Boolean,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(GHSpacing.Sm),
    ) {
        parseBlocks(content).forEach { block ->
            when (block) {
                is ContentBlock.Text -> Text(
                    text = block.value,
                    style = GHType.Body,
                    color = GHColors.TextPrimary,
                )

                is ContentBlock.Code -> GHCodeBlock(code = block.value)
            }
        }

        if (isStreaming) {
            Text(
                text = "▍",
                style = GHType.Code,
                color = GHColors.AccentBlue,
            )
        }
    }
}

private sealed interface ContentBlock {
    data class Text(val value: String) : ContentBlock
    data class Code(val language: String?, val value: String) : ContentBlock
}

private fun parseBlocks(content: String): List<ContentBlock> {
    val pieces = content.split("```")
    if (pieces.size <= 1) {
        return listOf(ContentBlock.Text(content))
    }

    return pieces.mapIndexedNotNull { index, piece ->
        if (index % 2 == 0) {
            if (piece.isEmpty()) null else ContentBlock.Text(piece)
        } else {
            val lines = piece.split('\n')
            val language = lines.firstOrNull()?.trim()?.takeIf { it.isNotEmpty() }
            val body = lines.drop(1).joinToString("\n")
            ContentBlock.Code(language = language, value = body)
        }
    }
}
