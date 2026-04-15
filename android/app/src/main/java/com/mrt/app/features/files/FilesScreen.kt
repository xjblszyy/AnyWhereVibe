package com.mrt.app.features.files

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import com.mrt.app.core.models.FileEntryModel
import com.mrt.app.core.models.FileViewerState
import com.mrt.app.core.models.FilesUnavailableReason
import com.mrt.app.core.models.FilesViewState
import com.mrt.app.designsystem.components.GHBadge
import com.mrt.app.designsystem.components.GHBanner
import com.mrt.app.designsystem.components.GHBannerTone
import com.mrt.app.designsystem.components.GHButton
import com.mrt.app.designsystem.components.GHButtonStyle
import com.mrt.app.designsystem.components.GHCard
import com.mrt.app.designsystem.components.GHCodeBlock
import com.mrt.app.designsystem.components.GHInput
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHRadii
import com.mrt.app.designsystem.theme.GHSpacing
import com.mrt.app.designsystem.theme.GHType

@Composable
fun FilesScreen(
    viewModel: FilesViewModel,
    modifier: Modifier = Modifier,
) {
    val state by androidx.compose.runtime.rememberUpdatedState(viewModel.state)
    Column(
        modifier = modifier
            .background(GHColors.BgPrimary)
            .verticalScroll(rememberScrollState())
            .padding(GHSpacing.Lg),
        verticalArrangement = Arrangement.spacedBy(GHSpacing.Lg),
    ) {
        Text("Files", style = GHType.TitleLg, color = GHColors.TextPrimary)

        when (val current = state) {
            is FilesViewState.Unavailable -> unavailableBanner(current.reason)
            is FilesViewState.LoadingDirectory -> GHBanner(
                title = "Loading Directory",
                message = "Loading ${pathLabel(current.path)}.",
                tone = GHBannerTone.Info,
            )
            is FilesViewState.DirectoryError -> GHBanner(
                title = "Directory Failed",
                message = current.message,
                tone = GHBannerTone.Warning,
            )
            is FilesViewState.DirectoryReady -> {
                pathBar(current.path, viewModel)
                createBar(viewModel)
                current.mutationMessage?.let {
                    GHBanner(title = "Updated", message = it, tone = GHBannerTone.Info)
                }
                directoryList(current.entries, viewModel)
                viewerSection(current.viewer, viewModel)
            }
        }
    }
}

@Composable
private fun unavailableBanner(reason: FilesUnavailableReason) {
    when (reason) {
        FilesUnavailableReason.DISCONNECTED -> GHBanner(title = "Agent Required", message = "Connect to the agent before browsing files.", tone = GHBannerTone.Info)
        FilesUnavailableReason.NO_ACTIVE_SESSION -> GHBanner(title = "Session Required", message = "Select or create a session before opening Files.", tone = GHBannerTone.Info)
        FilesUnavailableReason.SESSION_UNAVAILABLE -> GHBanner(title = "Session Unavailable", message = "The active session is no longer available on the agent.", tone = GHBannerTone.Warning)
    }
}

@Composable
private fun pathBar(path: String, viewModel: FilesViewModel) {
    GHCard {
        Text("Current Path", style = GHType.BodySm, color = GHColors.TextSecondary)
        Row(horizontalArrangement = Arrangement.spacedBy(GHSpacing.Sm)) {
            GHBadge(text = pathLabel(path), color = GHColors.AccentBlue)
            if (path.isNotEmpty()) {
                GHButton(
                    text = "Up",
                    onClick = viewModel::navigateUp,
                    style = GHButtonStyle.Secondary,
                )
            }
        }
    }
}

@Composable
private fun createBar(viewModel: FilesViewModel) {
    GHCard {
        GHInput(
            value = viewModel.draftName,
            onValueChange = { viewModel.draftName = it },
            placeholder = "folder/new.txt",
        )
        Row(horizontalArrangement = Arrangement.spacedBy(GHSpacing.Sm)) {
            GHButton(text = "New File", onClick = viewModel::createFile)
            GHButton(text = "New Folder", onClick = viewModel::createDirectory, style = GHButtonStyle.Secondary)
        }
    }
}

@Composable
private fun directoryList(entries: List<FileEntryModel>, viewModel: FilesViewModel) {
    GHCard {
        Text("Entries", style = GHType.BodySm, color = GHColors.TextSecondary)
        Column(verticalArrangement = Arrangement.spacedBy(GHSpacing.Sm)) {
            entries.forEach { entry ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(GHColors.BgSecondary, androidx.compose.foundation.shape.RoundedCornerShape(GHRadii.Md))
                        .clickable { viewModel.enter(entry) }
                        .padding(GHSpacing.Md)
                        .testTag("filesEntry:${entry.path}"),
                    horizontalArrangement = Arrangement.spacedBy(GHSpacing.Md),
                ) {
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(GHSpacing.Xs)) {
                        Text(entry.name, style = GHType.BodySm, color = GHColors.TextPrimary, fontWeight = FontWeight.SemiBold)
                        Text(entry.path, style = GHType.Caption, color = GHColors.TextSecondary)
                    }
                    GHBadge(text = if (entry.isDirectory) "Dir" else "File", color = if (entry.isDirectory) GHColors.AccentBlue else GHColors.TextSecondary)
                }
            }
        }
    }
}

@Composable
private fun viewerSection(viewer: FileViewerState, viewModel: FilesViewModel) {
    when (viewer) {
        FileViewerState.None -> Unit
        is FileViewerState.Loading -> GHBanner(
            title = "Loading File",
            message = "Opening ${viewer.path}.",
            tone = GHBannerTone.Info,
        )
        is FileViewerState.ReadOnly -> GHBanner(
            title = "Read Only",
            message = viewer.message,
            tone = GHBannerTone.Warning,
        )
        is FileViewerState.Error -> GHBanner(
            title = "File Failed",
            message = viewer.message,
            tone = GHBannerTone.Warning,
        )
        is FileViewerState.Editable -> GHCard {
            Text(viewer.path, style = GHType.BodySm, color = GHColors.TextSecondary)
            GHInput(
                value = viewer.content,
                onValueChange = viewModel::updateEditor,
                placeholder = "File content",
                minLines = 8,
                modifier = Modifier.testTag("filesEditor"),
            )
            GHInput(
                value = viewModel.renameDraft,
                onValueChange = { viewModel.renameDraft = it },
                placeholder = "new-name.txt",
            )
            Row(horizontalArrangement = Arrangement.spacedBy(GHSpacing.Sm)) {
                GHButton(
                    text = if (viewer.isSaving) "Saving" else "Save",
                    onClick = viewModel::saveCurrentFile,
                )
                GHButton(text = "Rename", onClick = viewModel::renameSelected, style = GHButtonStyle.Secondary)
                GHButton(text = "Delete", onClick = viewModel::deleteSelected, style = GHButtonStyle.Danger)
            }
            viewer.errorMessage?.let {
                GHBanner(title = "Save Failed", message = it, tone = GHBannerTone.Warning)
            }
            GHCodeBlock(code = viewer.content, modifier = Modifier.testTag("filesPreview"))
        }
    }
}

private fun pathLabel(path: String): String = if (path.isEmpty()) "Root" else path
