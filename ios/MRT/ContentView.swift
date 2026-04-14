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
    @StateObject private var sessionViewModel = SessionViewModel()

    private let preferences: Preferences

    init(
        connectionManager: ConnectionManaging = ConnectionManager(),
        preferences: Preferences = Preferences()
    ) {
        self.preferences = preferences
        _chatViewModel = StateObject(
            wrappedValue: ChatViewModel(connectionManager: connectionManager)
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
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
