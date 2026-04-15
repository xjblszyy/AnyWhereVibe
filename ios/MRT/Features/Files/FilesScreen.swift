import SwiftUI

struct FilesScreen: View {
    @ObservedObject var viewModel: FilesViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GHSpacing.lg) {
                Text("Files")
                    .font(GHTypography.titleLg)
                    .foregroundStyle(GHColors.textPrimary)

                switch viewModel.state {
                case .unavailable(let reason):
                    unavailableBanner(reason)
                case .loadingDirectory(let path):
                    GHBanner(tone: .info, title: "Loading Directory", message: "Loading \(pathLabel(path)).")
                case .directoryError(_, let message):
                    GHBanner(tone: .warning, title: "Directory Failed", message: message)
                case .directoryReady(let path, let entries, let viewer, let mutationMessage):
                    pathBar(path)
                    createBar
                    if let mutationMessage {
                        GHBanner(tone: .success, title: "Updated", message: mutationMessage)
                    }
                    directoryList(entries)
                    viewerSection(viewer)
                }
            }
            .padding(GHSpacing.xl)
        }
        .background(GHColors.bgPrimary)
    }

    @ViewBuilder
    private func unavailableBanner(_ reason: FilesUnavailableReason) -> some View {
        switch reason {
        case .disconnected:
            GHBanner(tone: .neutral, title: "Agent Required", message: "Connect to the agent before browsing files.")
        case .noActiveSession:
            GHBanner(tone: .neutral, title: "Session Required", message: "Select or create a session before opening Files.")
        case .sessionUnavailable:
            GHBanner(tone: .warning, title: "Session Unavailable", message: "The active session is no longer available on the agent.")
        }
    }

    private func pathBar(_ path: String) -> some View {
        GHCard {
            VStack(alignment: .leading, spacing: GHSpacing.sm) {
                Text("Current Path")
                    .font(GHTypography.bodySm)
                    .foregroundStyle(GHColors.textSecondary)
                HStack(spacing: GHSpacing.sm) {
                    GHBadge(text: pathLabel(path), color: GHColors.accentBlue)
                    if !path.isEmpty {
                        GHButton(title: "Up", icon: "arrow.up.left", style: .secondary) {
                            viewModel.navigateUp()
                        }
                    }
                }
            }
        }
    }

    private var createBar: some View {
        GHCard {
            VStack(alignment: .leading, spacing: GHSpacing.sm) {
                GHInput(title: "New Path", text: $viewModel.draftName, placeholder: "folder/new.txt")
                HStack(spacing: GHSpacing.sm) {
                    GHButton(title: "New File", icon: "doc.badge.plus", style: .primary) {
                        viewModel.createFile()
                    }
                    GHButton(title: "New Folder", icon: "folder.badge.plus", style: .secondary) {
                        viewModel.createDirectory()
                    }
                }
            }
        }
    }

    private func directoryList(_ entries: [FileEntryModel]) -> some View {
        GHList(title: "Entries") {
            ForEach(entries) { entry in
                Button {
                    viewModel.enter(entry)
                } label: {
                    HStack(spacing: GHSpacing.md) {
                        VStack(alignment: .leading, spacing: GHSpacing.xs) {
                            Text(entry.name)
                                .font(GHTypography.bodySm)
                                .foregroundStyle(GHColors.textPrimary)
                            Text(entry.path)
                                .font(GHTypography.caption)
                                .foregroundStyle(GHColors.textSecondary)
                        }
                        Spacer()
                        GHBadge(text: entry.isDirectory ? "Dir" : "File", color: entry.isDirectory ? GHColors.accentBlue : GHColors.textSecondary)
                    }
                    .padding(.horizontal, GHSpacing.md)
                    .padding(.vertical, GHSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("files.entry.\(sanitize(entry.path))")
            }
        }
    }

    @ViewBuilder
    private func viewerSection(_ viewer: FileViewerState) -> some View {
        switch viewer {
        case .none:
            EmptyView()
        case .loading(let path):
            GHBanner(tone: .info, title: "Loading File", message: "Opening \(path).")
        case .readOnly(_, let message):
            GHBanner(tone: .warning, title: "Read Only", message: message)
        case .error(_, let message):
            GHBanner(tone: .warning, title: "File Failed", message: message)
        case .editable(let path, let content, let isSaving, let errorMessage):
            GHCard {
                VStack(alignment: .leading, spacing: GHSpacing.sm) {
                    Text(path)
                        .font(GHTypography.bodySm)
                        .foregroundStyle(GHColors.textSecondary)
                    TextEditor(text: Binding(
                        get: { content },
                        set: { viewModel.updateEditor($0) }
                    ))
                    .font(GHTypography.code)
                    .frame(minHeight: 220)
                    .scrollContentBackground(.hidden)
                    .background(GHColors.bgPrimary)
                    .accessibilityIdentifier("files.editor")

                    GHInput(title: "Rename To", text: $viewModel.renameDraft, placeholder: "new-name.txt")

                    HStack(spacing: GHSpacing.sm) {
                        GHButton(title: isSaving ? "Saving" : "Save", icon: "square.and.arrow.down", style: .primary) {
                            viewModel.saveCurrentFile()
                        }
                        GHButton(title: "Rename", icon: "pencil", style: .secondary) {
                            viewModel.renameSelected()
                        }
                        GHButton(title: "Delete", icon: "trash", style: .danger) {
                            viewModel.deleteSelected()
                        }
                    }

                    if let errorMessage {
                        GHBanner(tone: .warning, title: "Save Failed", message: errorMessage)
                    }
                }
            }
        }
    }

    private func sanitize(_ path: String) -> String {
        path.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: " ", with: "_")
    }

    private func pathLabel(_ path: String) -> String {
        path.isEmpty ? "Root" : path
    }
}
