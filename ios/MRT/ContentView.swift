import SwiftUI

struct ContentView: View {
    private enum Tab: String, CaseIterable {
        case chat = "Chat"
        case sessions = "Sessions"
        case git = "Git"
        case files = "Files"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .chat:
                return "bubble.left.and.text.bubble.right"
            case .sessions:
                return "rectangle.stack"
            case .git:
                return "point.topleft.down.curvedto.point.bottomright.up"
            case .files:
                return "folder"
            case .settings:
                return "gearshape"
            }
        }
    }

    @State private var selectedTab: Tab = .chat

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .chat:
                    chatPlaceholder
                case .sessions:
                    sessionsPlaceholder
                case .git:
                    gitPlaceholder
                case .files:
                    filesPlaceholder
                case .settings:
                    settingsPlaceholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .overlay(GHColors.borderDefault)

            GHTabBar(
                items: Tab.allCases.map { tab in
                    GHTabItem(
                        id: tab,
                        title: tab.rawValue,
                        systemImage: tab.icon
                    )
                },
                selection: $selectedTab
            )
        }
        .background(GHColors.bgPrimary.ignoresSafeArea())
    }

    private var chatPlaceholder: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GHSpacing.lg) {
                header(
                    title: "Chat",
                    subtitle: "Threaded terminal chat will land in a later task."
                )

                GHBanner(
                    tone: .info,
                    title: "App Shell Ready",
                    message: "This placeholder keeps the navigation and design system buildable while networking and models are still out of scope."
                )

                GHCard {
                    VStack(alignment: .leading, spacing: GHSpacing.md) {
                        HStack {
                            GHBadge(text: "Preview", color: GHColors.accentBlue)
                            Spacer()
                            GHStatusDot(status: .pending)
                        }

                        Text("Local Agent")
                            .font(GHTypography.title)
                            .foregroundStyle(GHColors.textPrimary)

                        Text("Connection, streaming, approvals, and protobuf-backed chat will be added in later tasks.")
                            .font(GHTypography.body)
                            .foregroundStyle(GHColors.textSecondary)

                        GHInput(
                            title: "Prompt",
                            text: .constant(""),
                            placeholder: "Task 6 intentionally stops at the shell."
                        )

                        HStack(spacing: GHSpacing.sm) {
                            GHButton(title: "Connect", icon: "bolt.horizontal", style: .primary) {}
                            GHButton(title: "Approve", icon: "checkmark.shield", style: .secondary) {}
                        }
                    }
                }

                GHCodeBlock(
                    code: "$ cargo run -p agent -- --mock --listen 0.0.0.0:9876",
                    language: "bash"
                )
            }
            .padding(GHSpacing.xl)
        }
    }

    private var sessionsPlaceholder: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GHSpacing.lg) {
                header(
                    title: "Sessions",
                    subtitle: "The dedicated sessions flow will reuse the later sidebar model."
                )

                GHList(title: "Recent") {
                    GHListRow(
                        title: "Mock Session",
                        subtitle: "Waiting for live transport",
                        trailing: AnyView(GHBadge(text: "Active", color: GHColors.accentGreen))
                    )
                    GHListRow(
                        title: "Planning",
                        subtitle: "No persisted sessions yet",
                        trailing: AnyView(GHStatusDot(status: .offline))
                    )
                }
            }
            .padding(GHSpacing.xl)
        }
    }

    private var gitPlaceholder: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GHSpacing.lg) {
                header(
                    title: "Git",
                    subtitle: "Git views are out of scope for Task 6."
                )

                GHDiffView(
                    title: "Diff Preview",
                    lines: [
                        .init(kind: .context, content: "diff --git a/app.swift b/app.swift"),
                        .init(kind: .addition, content: "+ UI shell will be wired in a later task"),
                        .init(kind: .deletion, content: "- Placeholder copy"),
                    ]
                )
            }
            .padding(GHSpacing.xl)
        }
    }

    private var filesPlaceholder: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GHSpacing.lg) {
                header(
                    title: "Files",
                    subtitle: "The file browser will arrive once transport and data models exist."
                )

                GHBanner(
                    tone: .neutral,
                    title: "Placeholder",
                    message: "Task 6 preserves the five-tab navigation shape without adding any file operations yet."
                )
            }
            .padding(GHSpacing.xl)
        }
    }

    private var settingsPlaceholder: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GHSpacing.lg) {
                header(
                    title: "Settings",
                    subtitle: "Connection and preferences screens are deferred."
                )

                GHCard {
                    VStack(alignment: .leading, spacing: GHSpacing.md) {
                        GHList(title: "Defaults") {
                            GHListRow(title: "Theme", subtitle: "Dark", trailing: AnyView(EmptyView()))
                            GHListRow(title: "Transport", subtitle: "LAN WebSocket", trailing: AnyView(EmptyView()))
                            GHListRow(title: "Approvals", subtitle: "Inline banners", trailing: AnyView(EmptyView()))
                        }
                    }
                }
            }
            .padding(GHSpacing.xl)
        }
    }

    private func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: GHSpacing.sm) {
            Text(title)
                .font(GHTypography.titleLg)
                .foregroundStyle(GHColors.textPrimary)

            Text(subtitle)
                .font(GHTypography.body)
                .foregroundStyle(GHColors.textSecondary)
        }
    }
}

#Preview {
    ContentView()
}
