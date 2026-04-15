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
    @StateObject private var chatViewModel: ChatViewModel
    @StateObject private var sessionViewModel: SessionViewModel
    @StateObject private var phoneWatchBridge: PhoneWatchBridge
    @StateObject private var preferences: Preferences

    init(
        connectionManager: ConnectionManaging = ConnectionManager(),
        preferences: Preferences = Preferences()
    ) {
        let sessionViewModel = SessionViewModel(connectionManager: connectionManager)
        let chatViewModel = ChatViewModel(connectionManager: connectionManager)

        _preferences = StateObject(wrappedValue: preferences)
        _sessionViewModel = StateObject(wrappedValue: sessionViewModel)
        _chatViewModel = StateObject(wrappedValue: chatViewModel)
        _phoneWatchBridge = StateObject(
            wrappedValue: PhoneWatchBridge(
                approvalResponder: { approvalID, approved in
                    Task {
                        try? await connectionManager.respondToApproval(approvalID, approved: approved)
                    }
                },
                quickActionHandler: { action, sessionID in
                    switch action {
                    case .cancel:
                        Task {
                            try? await connectionManager.cancelTask(sessionID: sessionID)
                        }
                        return true
                    case .retry, .continue:
                        return false
                    }
                },
                sessionSelectionHandler: { sessionID in
                    sessionViewModel.selectSession(id: sessionID)
                    return true
                }
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .chat:
                    ChatView(viewModel: chatViewModel, sessionViewModel: sessionViewModel)
                case .sessions:
                    SessionsScreen(viewModel: sessionViewModel)
                case .git:
                    GitPlaceholderView()
                case .files:
                    FilesPlaceholderView()
                case .settings:
                    SettingsView(preferences: preferences)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .overlay(GHColors.borderDefault)

            GHTabBar(
                items: Tab.allCases.map { tab in
                    GHTabItem(id: tab, title: tab.rawValue, systemImage: tab.icon)
                },
                selection: $selectedTab
            )
        }
        .background(GHColors.bgPrimary.ignoresSafeArea())
        .task(id: watchBridgeSyncSignature) {
            phoneWatchBridge.sync(snapshot: makeWatchSnapshot())
        }
        .onAppear {
            chatViewModel.activeSessionID = sessionViewModel.activeSessionID
        }
        .onChange(of: sessionViewModel.activeSessionID) { _, newValue in
            chatViewModel.activeSessionID = newValue
        }
        .task(id: preferences.connectionConfigurationSignature) {
            guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
                return
            }
            await chatViewModel.connectIfNeeded(
                host: preferences.directHost,
                port: preferences.directPort,
                mode: preferences.connectionMode
            )
        }
    }

    private var watchBridgeSyncSignature: String {
        let sessionSignature = sessionViewModel.sessions
            .map { "\($0.id):\($0.status.rawValue):\($0.lastActiveMs)" }
            .joined(separator: "|")
        let approvalSignature = chatViewModel.pendingApproval?.approvalID ?? "none"
        let activeSessionSignature = sessionViewModel.activeSessionID ?? "none"
        return [
            "\(chatViewModel.connectionState)",
            sessionSignature,
            activeSessionSignature,
            approvalSignature,
            lastWatchSummary ?? "none",
            chatViewModel.lastMessageSignature,
        ].joined(separator: "::")
    }

    private var lastWatchSummary: String? {
        chatViewModel.messages
            .last(where: { message in
                message.sessionID == sessionViewModel.activeSessionID && message.role != .user
            })?
            .content
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeWatchSnapshot() -> PhoneWatchBridge.Snapshot {
        PhoneWatchBridge.Snapshot(
            connectionState: chatViewModel.connectionState,
            sessions: sessionViewModel.sessions,
            activeSessionID: sessionViewModel.activeSessionID,
            lastSummary: lastWatchSummary,
            pendingApproval: chatViewModel.pendingApproval
        )
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
