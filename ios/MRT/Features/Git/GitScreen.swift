import SwiftUI

struct GitScreen: View {
    @ObservedObject var viewModel: GitViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GHSpacing.lg) {
                Text("Git")
                    .font(GHTypography.titleLg)
                    .foregroundStyle(GHColors.textPrimary)

                switch viewModel.state {
                case .unavailable(let reason):
                    unavailableBanner(reason)
                case .loadingStatus:
                    GHBanner(
                        tone: .info,
                        title: "Loading Git Status",
                        message: "Inspecting the active session repository."
                    )
                case .statusError(let message):
                    GHBanner(
                        tone: .warning,
                        title: "Git Status Failed",
                        message: message
                    )
                case .readyClean(let summary):
                    summaryCard(summary)
                    GHBanner(
                        tone: .success,
                        title: "Working Tree Clean",
                        message: "No worktree-visible changes in this session."
                    )
                case .readyDirty(let summary, let selectedPath, let diff):
                    summaryCard(summary)
                    changedFiles(summary: summary, selectedPath: selectedPath)
                    diffSection(diff)
                }
            }
            .padding(GHSpacing.xl)
        }
        .background(GHColors.bgPrimary)
    }

    @ViewBuilder
    private func unavailableBanner(_ reason: GitUnavailableReason) -> some View {
        switch reason {
        case .disconnected:
            GHBanner(tone: .neutral, title: "Agent Required", message: "Connect to the agent before loading Git status.")
        case .noActiveSession:
            GHBanner(tone: .neutral, title: "Session Required", message: "Select or create a session before opening Git.")
        case .sessionUnavailable:
            GHBanner(tone: .warning, title: "Session Unavailable", message: "The active session is no longer available on the agent.")
        case .notRepository:
            GHBanner(tone: .neutral, title: "Not a Git Repository", message: "The active session is not inside a Git repository.")
        }
    }

    private func summaryCard(_ summary: GitSummaryModel) -> some View {
        GHCard {
            VStack(alignment: .leading, spacing: GHSpacing.sm) {
                Text("Repository Summary")
                    .font(GHTypography.bodySm)
                    .foregroundStyle(GHColors.textSecondary)

                HStack(spacing: GHSpacing.sm) {
                    Text(summary.branch)
                        .font(GHTypography.title)
                        .foregroundStyle(GHColors.textPrimary)
                    GHBadge(
                        text: summary.isClean ? "Clean" : "Dirty",
                        color: summary.isClean ? GHColors.accentGreen : GHColors.accentOrange
                    )
                }

                if !summary.tracking.isEmpty {
                    Text(summary.tracking)
                        .font(GHTypography.caption)
                        .foregroundStyle(GHColors.textSecondary)
                }
            }
        }
    }

    private func changedFiles(summary: GitSummaryModel, selectedPath: String) -> some View {
        GHList(title: "Changed Files") {
            ForEach(summary.files) { file in
                Button {
                    viewModel.selectFile(path: file.path)
                } label: {
                    HStack(spacing: GHSpacing.md) {
                        VStack(alignment: .leading, spacing: GHSpacing.xs) {
                            Text(file.path)
                                .font(GHTypography.bodySm)
                                .foregroundStyle(GHColors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GHBadge(text: file.status.capitalized, color: badgeColor(file.status))
                    }
                    .padding(.horizontal, GHSpacing.md)
                    .padding(.vertical, GHSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selectedPath == file.path ? GHColors.bgTertiary : GHColors.bgSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("git.file.\(sanitizeIdentifier(file.path))")
            }
        }
    }

    @ViewBuilder
    private func diffSection(_ diff: GitDiffState) -> some View {
        switch diff {
        case .idle:
            EmptyView()
        case .loading(let path):
            GHBanner(
                tone: .info,
                title: "Loading Diff",
                message: "Loading diff for \(path)."
            )
        case .error(_, let message):
            GHBanner(
                tone: .warning,
                title: "Diff Failed",
                message: message
            )
        case .ready(let content):
            GHDiffView(
                title: content.path,
                lines: diffLines(from: content.rawDiff)
            )
        }
    }

    private func diffLines(from rawDiff: String) -> [GHDiffLine] {
        rawDiff
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let value = String(line)
                if value.hasPrefix("+"), !value.hasPrefix("+++") {
                    return GHDiffLine(kind: .addition, content: value)
                }
                if value.hasPrefix("-"), !value.hasPrefix("---") {
                    return GHDiffLine(kind: .deletion, content: value)
                }
                return GHDiffLine(kind: .context, content: value)
            }
    }

    private func badgeColor(_ status: String) -> Color {
        switch status {
        case "modified":
            return GHColors.accentOrange
        case "deleted":
            return GHColors.accentRed
        case "untracked":
            return GHColors.accentBlue
        default:
            return GHColors.textSecondary
        }
    }

    private func sanitizeIdentifier(_ path: String) -> String {
        path
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}
