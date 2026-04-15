package com.mrt.app.features.git

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.mrt.app.core.models.GitDiffState
import com.mrt.app.core.models.GitSummaryModel
import com.mrt.app.core.models.GitUnavailableReason
import com.mrt.app.core.models.GitViewState
import com.mrt.app.designsystem.components.GHBadge
import com.mrt.app.designsystem.components.GHBanner
import com.mrt.app.designsystem.components.GHBannerTone
import com.mrt.app.designsystem.components.GHCard
import com.mrt.app.designsystem.components.GHDiffKind
import com.mrt.app.designsystem.components.GHDiffLine
import com.mrt.app.designsystem.components.GHDiffView
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHRadii
import com.mrt.app.designsystem.theme.GHSpacing
import com.mrt.app.designsystem.theme.GHType

@Composable
fun GitScreen(
    viewModel: GitViewModel,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .background(GHColors.BgPrimary)
            .verticalScroll(rememberScrollState())
            .padding(GHSpacing.Lg),
        verticalArrangement = Arrangement.spacedBy(GHSpacing.Lg),
    ) {
        Text(
            text = "Git",
            style = GHType.TitleLg,
            color = GHColors.TextPrimary,
        )

        when (val state = viewModel.state) {
            is GitViewState.Unavailable -> unavailableBanner(state.reason)
            GitViewState.LoadingStatus -> GHBanner(
                title = "Loading Git Status",
                message = "Inspecting the active session repository.",
                tone = GHBannerTone.Info,
            )
            is GitViewState.StatusError -> GHBanner(
                title = "Git Status Failed",
                message = state.message,
                tone = GHBannerTone.Warning,
            )
            is GitViewState.ReadyClean -> {
                summaryCard(state.summary)
                GHBanner(
                    title = "Working Tree Clean",
                    message = "No worktree-visible changes in this session.",
                    tone = GHBannerTone.Info,
                )
            }
            is GitViewState.ReadyDirty -> {
                summaryCard(state.summary)
                changedFiles(state.summary, state.selectedPath, viewModel::selectFile)
                diffSection(state.diff)
            }
        }
    }
}

@Composable
private fun unavailableBanner(reason: GitUnavailableReason) {
    when (reason) {
        GitUnavailableReason.DISCONNECTED -> GHBanner(
            title = "Agent Required",
            message = "Connect to the agent before loading Git status.",
            tone = GHBannerTone.Info,
        )
        GitUnavailableReason.NO_ACTIVE_SESSION -> GHBanner(
            title = "Session Required",
            message = "Select or create a session before opening Git.",
            tone = GHBannerTone.Info,
        )
        GitUnavailableReason.SESSION_UNAVAILABLE -> GHBanner(
            title = "Session Unavailable",
            message = "The active session is no longer available on the agent.",
            tone = GHBannerTone.Warning,
        )
        GitUnavailableReason.NOT_REPOSITORY -> GHBanner(
            title = "Not a Git Repository",
            message = "The active session is not inside a Git repository.",
            tone = GHBannerTone.Info,
        )
    }
}

@Composable
private fun summaryCard(summary: GitSummaryModel) {
    GHCard {
        Column(verticalArrangement = Arrangement.spacedBy(GHSpacing.Sm)) {
            Text("Repository Summary", style = GHType.BodySm, color = GHColors.TextSecondary)
            Row(horizontalArrangement = Arrangement.spacedBy(GHSpacing.Sm)) {
                Text(
                    text = summary.branch,
                    style = GHType.Title,
                    color = GHColors.TextPrimary,
                    fontWeight = FontWeight.SemiBold,
                )
                GHBadge(
                    text = if (summary.isClean) "Clean" else "Dirty",
                    color = if (summary.isClean) GHColors.AccentGreen else GHColors.AccentOrange,
                )
            }
            if (summary.tracking.isNotBlank()) {
                Text(summary.tracking, style = GHType.Caption, color = GHColors.TextSecondary)
            }
        }
    }
}

@Composable
private fun changedFiles(
    summary: GitSummaryModel,
    selectedPath: String,
    onSelect: (String) -> Unit,
) {
    GHCard {
        Text("Changed Files", style = GHType.BodySm, color = GHColors.TextSecondary)
        Column(modifier = Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(GHSpacing.Sm)) {
            summary.files.forEach { file ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(
                            if (file.path == selectedPath) GHColors.BgTertiary else GHColors.BgSecondary,
                            androidx.compose.foundation.shape.RoundedCornerShape(GHRadii.Md),
                        )
                        .clickable { onSelect(file.path) }
                        .padding(GHSpacing.Md)
                        .testTag("gitFile:${file.path}"),
                    horizontalArrangement = Arrangement.spacedBy(GHSpacing.Md),
                ) {
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(GHSpacing.Xs)) {
                        Text(file.path, style = GHType.BodySm, color = GHColors.TextPrimary)
                    }
                    GHBadge(text = file.status.replaceFirstChar { it.uppercase() }, color = badgeColor(file.status))
                }
            }
        }
    }
}

@Composable
private fun diffSection(diff: GitDiffState) {
    when (diff) {
        GitDiffState.Idle -> Unit
        is GitDiffState.Loading -> GHBanner(
            title = "Loading Diff",
            message = "Loading diff for ${diff.path}.",
            tone = GHBannerTone.Info,
        )
        is GitDiffState.Error -> GHBanner(
            title = "Diff Failed",
            message = diff.message,
            tone = GHBannerTone.Warning,
        )
        is GitDiffState.Ready -> GHDiffView(
            title = diff.content.path,
            lines = diff.content.rawDiff.lines().map { line ->
                when {
                    line.startsWith("+") && !line.startsWith("+++") -> GHDiffLine(GHDiffKind.Added, line)
                    line.startsWith("-") && !line.startsWith("---") -> GHDiffLine(GHDiffKind.Removed, line)
                    else -> GHDiffLine(GHDiffKind.Context, line)
                }
            },
            modifier = Modifier.testTag("gitDiff"),
        )
    }
}

private fun badgeColor(status: String) = when (status) {
    "modified" -> GHColors.AccentOrange
    "deleted" -> GHColors.AccentRed
    "untracked" -> GHColors.AccentBlue
    else -> GHColors.TextSecondary
}
