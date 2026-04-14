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

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [FeatureChatMessage] = []
    @Published var inputText = ""
    @Published var connectionState: ConnectionState
    @Published var pendingApproval: Mrt_ApprovalRequest? {
        didSet {
            if pendingApproval != nil {
                connectionState = .showingApproval
            } else if connectionState == .showingApproval {
                connectionState = .connected
            }
        }
    }
    @Published var activeSessionID: String? = "session-1"

    private let connectionManager: ConnectionManaging

    init(connectionManager: ConnectionManaging) {
        self.connectionManager = connectionManager
        self.connectionState = connectionManager.state
    }

    var isLoading: Bool {
        get { connectionState == .loading }
        set {
            if newValue {
                connectionState = .loading
            } else if connectionState == .loading {
                connectionState = .connected
            }
        }
    }

    func sendPrompt() async {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        messages.append(
            FeatureChatMessage(
                sessionID: activeSessionID,
                content: prompt,
                isComplete: true,
                role: .user
            )
        )
        inputText = ""
        connectionState = .loading

        do {
            try await connectionManager.sendPrompt(prompt, sessionID: activeSessionID ?? "session-1")
        } catch {
            messages.append(
                FeatureChatMessage(
                    sessionID: activeSessionID,
                    content: "Unable to send prompt right now.",
                    isComplete: true,
                    role: .system
                )
            )
            connectionState = .connected
        }
    }

    func respondToApproval(_ approved: Bool) {
        pendingApproval = nil
        messages.append(
            FeatureChatMessage(
                sessionID: activeSessionID,
                content: approved ? "Approval queued." : "Approval rejected.",
                isComplete: true,
                role: .system
            )
        )
    }
}

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var sessions: [SessionModel]
    @Published var activeSessionID: String?

    init(sessions: [SessionModel]? = nil) {
        let initialSessions = sessions ?? Self.defaultSessions
        self.sessions = initialSessions
        self.activeSessionID = initialSessions.first?.id
    }

    func selectSession(id: String) {
        activeSessionID = id
    }

    func createSession(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let session = SessionModel(
            id: UUID().uuidString,
            name: trimmedName,
            status: .idle,
            createdAtMs: Self.nowMilliseconds(),
            lastActiveMs: Self.nowMilliseconds(),
            workingDirectory: "/tmp/\(trimmedName.replacingOccurrences(of: " ", with: "-").lowercased())"
        )
        sessions.insert(session, at: 0)
        activeSessionID = session.id
    }

    private static var defaultSessions: [SessionModel] {
        [
            SessionModel(
                id: "session-1",
                name: "Main Session",
                status: .running,
                createdAtMs: nowMilliseconds(),
                lastActiveMs: nowMilliseconds(),
                workingDirectory: "/Users/mac/Desktop/AnyWhereVibe"
            ),
            SessionModel(
                id: "session-2",
                name: "Planning",
                status: .idle,
                createdAtMs: nowMilliseconds(),
                lastActiveMs: nowMilliseconds(),
                workingDirectory: "/Users/mac/Desktop"
            ),
        ]
    }

    private static func nowMilliseconds() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1_000)
    }
}

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var sessionViewModel: SessionViewModel

    @State private var showSessionSidebar = false

    var body: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                HStack(spacing: GHSpacing.sm) {
                    GHButton(title: "Sessions", icon: "sidebar.leading", style: .secondary) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSessionSidebar.toggle()
                        }
                    }

                    VStack(alignment: .leading, spacing: GHSpacing.xs) {
                        Text(sessionTitle)
                            .font(GHTypography.title)
                            .foregroundStyle(GHColors.textPrimary)

                        Text("Threaded terminal chat")
                            .font(GHTypography.caption)
                            .foregroundStyle(GHColors.textSecondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, GHSpacing.lg)
                .padding(.vertical, GHSpacing.md)

                ConnectionStatusBar(state: viewModel.connectionState)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: GHSpacing.md) {
                            if viewModel.messages.isEmpty {
                                GHBanner(
                                    tone: .info,
                                    title: "No messages yet",
                                    message: "Send a prompt once your LAN settings are configured."
                                )
                            }

                            ForEach(viewModel.messages) { message in
                                ThreadMessageView(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(GHSpacing.lg)
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        guard let lastID = viewModel.messages.last?.id else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }

                if let request = viewModel.pendingApproval {
                    ApprovalBannerView(
                        request: request,
                        onApprove: { viewModel.respondToApproval(true) },
                        onReject: { viewModel.respondToApproval(false) }
                    )
                    .padding(.horizontal, GHSpacing.lg)
                    .padding(.bottom, GHSpacing.md)
                }

                PromptInputBar(
                    text: $viewModel.inputText,
                    isDisabled: viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onSend: {
                        Task { await viewModel.sendPrompt() }
                    }
                )
            }

            if showSessionSidebar {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSessionSidebar = false
                        }
                    }

                SessionSidebarView(viewModel: sessionViewModel)
                    .transition(.move(edge: .leading))
            }
        }
        .background(GHColors.bgPrimary)
        .onAppear {
            viewModel.activeSessionID = sessionViewModel.activeSessionID
        }
        .onChange(of: sessionViewModel.activeSessionID) { _, newValue in
            viewModel.activeSessionID = newValue
        }
    }

    private var sessionTitle: String {
        sessionViewModel.sessions.first(where: { $0.id == sessionViewModel.activeSessionID })?.name ?? "Chat"
    }
}

struct ThreadMessageView: View {
    let message: FeatureChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: GHSpacing.xl * 2)
            }

            VStack(alignment: .leading, spacing: GHSpacing.sm) {
                HStack(spacing: GHSpacing.sm) {
                    Text(roleTitle)
                        .font(GHTypography.bodySm)
                        .fontWeight(.semibold)
                        .foregroundStyle(roleAccent)
                    Spacer()
                    Text(message.timeAgo)
                        .font(GHTypography.caption)
                        .foregroundStyle(GHColors.textTertiary)
                }

                if message.role == .assistant {
                    StreamingTextView(content: message.content, isStreaming: !message.isComplete)
                } else {
                    Text(message.content)
                        .font(GHTypography.body)
                        .foregroundStyle(GHColors.textPrimary)
                }
            }
            .padding(GHSpacing.md)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: GHRadius.lg)
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: GHRadius.lg))

            if message.role != .user {
                Spacer(minLength: GHSpacing.xl * 2)
            }
        }
    }

    private var roleTitle: String {
        switch message.role {
        case .assistant:
            return "Codex"
        case .system:
            return "System"
        case .user:
            return "You"
        }
    }

    private var roleAccent: Color {
        switch message.role {
        case .assistant:
            return GHColors.accentBlue
        case .system:
            return GHColors.accentOrange
        case .user:
            return GHColors.textPrimary
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .assistant:
            return GHColors.bgSecondary
        case .system:
            return GHColors.bgTertiary
        case .user:
            return GHColors.bgOverlay
        }
    }

    private var borderColor: Color {
        message.role == .user ? GHColors.accentBlue.opacity(0.3) : GHColors.borderDefault
    }
}

struct StreamingTextView: View {
    let content: String
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: GHSpacing.sm) {
            ForEach(Array(parsedBlocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let value):
                    Text(value)
                        .font(GHTypography.body)
                        .foregroundStyle(GHColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code(let language, let value):
                    GHCodeBlock(code: value, language: language)
                }
            }

            if isStreaming {
                Text("▍")
                    .font(GHTypography.code)
                    .foregroundStyle(GHColors.accentBlue)
            }
        }
    }

    private var parsedBlocks: [ContentBlock] {
        let pieces = content.components(separatedBy: "```")
        guard pieces.count > 1 else {
            return [.text(content)]
        }

        return pieces.enumerated().compactMap { index, piece in
            if index.isMultiple(of: 2) {
                return piece.isEmpty ? nil : .text(piece)
            }

            let lines = piece.split(separator: "\n", omittingEmptySubsequences: false)
            let language = lines.first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = lines.dropFirst().joined(separator: "\n")
            return .code(language: language?.isEmpty == true ? nil : language, value: body)
        }
    }

    private enum ContentBlock {
        case text(String)
        case code(language: String?, value: String)
    }
}

struct ApprovalBannerView: View {
    let request: Mrt_ApprovalRequest
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        GHCard {
            VStack(alignment: .leading, spacing: GHSpacing.md) {
                HStack {
                    Text("Permission Required")
                        .font(GHTypography.bodySm)
                        .fontWeight(.semibold)
                        .foregroundStyle(GHColors.accentYellow)
                    Spacer()
                    GHBadge(text: request.approvalType.displayName, color: GHColors.accentYellow)
                }

                Text(request.description_p)
                    .font(GHTypography.bodySm)
                    .foregroundStyle(GHColors.textSecondary)

                if !request.command.isEmpty {
                    GHCodeBlock(code: request.command, language: "bash")
                }

                HStack(spacing: GHSpacing.sm) {
                    GHButton(title: "Reject", icon: "xmark", style: .danger, action: onReject)
                    GHButton(title: "Approve", icon: "checkmark", style: .primary, action: onApprove)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: GHRadius.lg)
                .stroke(GHColors.accentYellow.opacity(0.45), lineWidth: 1)
        )
    }
}

struct ConnectionStatusBar: View {
    let state: ConnectionState

    var body: some View {
        HStack(spacing: GHSpacing.sm) {
            GHStatusDot(status: dotStatus)
            Text(statusText)
                .font(GHTypography.caption)
                .foregroundStyle(GHColors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, GHSpacing.lg)
        .padding(.vertical, GHSpacing.sm)
        .background(GHColors.bgSecondary)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(GHColors.borderMuted)
                .frame(height: 1)
        }
    }

    private var statusText: String {
        switch state {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting to LAN agent"
        case .connected:
            return "Connected"
        case .loading:
            return "Waiting for response"
        case .showingApproval:
            return "Approval required"
        case .reconnecting:
            return "Reconnecting"
        }
    }

    private var dotStatus: GHStatusDot.Status {
        switch state {
        case .connected:
            return .online
        case .connecting, .loading, .showingApproval, .reconnecting:
            return .pending
        case .disconnected:
            return .offline
        }
    }
}

struct PromptInputBar: View {
    @Binding var text: String
    let isDisabled: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: GHSpacing.sm) {
            GHInput(title: nil, text: $text, placeholder: "Send a prompt to the active session")
            GHButton(title: "Send", icon: "paperplane.fill", style: .primary, action: onSend)
                .opacity(isDisabled ? 0.5 : 1)
                .disabled(isDisabled)
        }
        .padding(GHSpacing.lg)
        .background(GHColors.bgSecondary)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(GHColors.borderMuted)
                .frame(height: 1)
        }
    }
}

struct SessionSidebarView: View {
    @ObservedObject var viewModel: SessionViewModel

    @State private var draftName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: GHSpacing.md) {
            Text("Sessions")
                .font(GHTypography.title)
                .foregroundStyle(GHColors.textPrimary)
                .padding(.top, GHSpacing.xl)
                .padding(.horizontal, GHSpacing.lg)

            HStack(spacing: GHSpacing.sm) {
                GHInput(title: nil, text: $draftName, placeholder: "New session")
                GHButton(title: "New", icon: "plus", style: .primary) {
                    viewModel.createSession(named: draftName)
                    draftName = ""
                }
            }
            .padding(.horizontal, GHSpacing.lg)

            ScrollView {
                LazyVStack(spacing: GHSpacing.sm) {
                    ForEach(viewModel.sessions) { session in
                        SessionRowView(
                            session: session,
                            isActive: session.id == viewModel.activeSessionID,
                            onSelect: { viewModel.selectSession(id: session.id) }
                        )
                    }
                }
                .padding(.horizontal, GHSpacing.lg)
                .padding(.bottom, GHSpacing.xl)
            }
        }
        .frame(width: 300)
        .background(GHColors.bgSecondary)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(GHColors.borderDefault)
                .frame(width: 1)
        }
    }
}

struct SessionsScreen: View {
    @ObservedObject var viewModel: SessionViewModel

    @State private var draftName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GHSpacing.lg) {
                Text("Sessions")
                    .font(GHTypography.titleLg)
                    .foregroundStyle(GHColors.textPrimary)

                GHCard {
                    HStack(spacing: GHSpacing.sm) {
                        GHInput(title: "Create Session", text: $draftName, placeholder: "Name")
                        GHButton(title: "Create", icon: "plus", style: .primary) {
                            viewModel.createSession(named: draftName)
                            draftName = ""
                        }
                    }
                }

                GHList(title: "Available") {
                    ForEach(viewModel.sessions) { session in
                        SessionRowView(
                            session: session,
                            isActive: session.id == viewModel.activeSessionID,
                            onSelect: { viewModel.selectSession(id: session.id) }
                        )
                    }
                }
            }
            .padding(GHSpacing.xl)
        }
        .background(GHColors.bgPrimary)
    }
}

struct SessionRowView: View {
    let session: SessionModel
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: GHSpacing.md) {
                VStack(alignment: .leading, spacing: GHSpacing.xs) {
                    Text(session.name)
                        .font(GHTypography.bodySm)
                        .foregroundStyle(GHColors.textPrimary)

                    Text(session.workingDirectory)
                        .font(GHTypography.caption)
                        .foregroundStyle(GHColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                GHBadge(text: session.status.displayName, color: isActive ? GHColors.accentBlue : GHColors.textTertiary)
            }
            .padding(GHSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? GHColors.bgTertiary : GHColors.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: GHRadius.md)
                    .stroke(isActive ? GHColors.accentBlue.opacity(0.35) : GHColors.borderDefault, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: GHRadius.md))
        }
        .buttonStyle(.plain)
    }
}

struct SettingsView: View {
    let preferences: Preferences

    @State private var mode: ConnectionMode
    @State private var host: String
    @State private var portText: String
    @State private var didSave = false

    init(preferences: Preferences) {
        self.preferences = preferences
        _mode = State(initialValue: preferences.connectionMode)
        _host = State(initialValue: preferences.directHost)
        _portText = State(initialValue: String(preferences.directPort))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GHSpacing.lg) {
                Text("Settings")
                    .font(GHTypography.titleLg)
                    .foregroundStyle(GHColors.textPrimary)

                GHCard {
                    VStack(alignment: .leading, spacing: GHSpacing.md) {
                        Text("Connection Mode")
                            .font(GHTypography.bodySm)
                            .foregroundStyle(GHColors.textSecondary)

                        Picker("Connection Mode", selection: $mode) {
                            Text("Direct LAN").tag(ConnectionMode.direct)
                            Text("Managed").tag(ConnectionMode.managed)
                        }
                        .pickerStyle(.segmented)

                        GHInput(title: "Host", text: $host, placeholder: "192.168.1.25")
                            .opacity(mode == .direct ? 1 : 0.6)

                        GHInput(title: "Port", text: $portText, placeholder: "9876")
                            .opacity(mode == .direct ? 1 : 0.6)

                        if let validationMessage {
                            GHBanner(
                                tone: .warning,
                                title: "Validation",
                                message: validationMessage
                            )
                        } else if didSave {
                            GHBanner(
                                tone: .success,
                                title: "Saved",
                                message: "Connection preferences updated."
                            )
                        }

                        GHButton(title: "Save Settings", icon: "checkmark", style: .primary) {
                            save()
                        }
                    }
                }
            }
            .padding(GHSpacing.xl)
        }
        .background(GHColors.bgPrimary)
    }

    private var validationMessage: String? {
        guard mode == .direct else { return nil }
        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Host is required for direct LAN mode."
        }
        guard let port = Int(portText), (1...65_535).contains(port) else {
            return "Port must be a number between 1 and 65535."
        }
        return nil
    }

    private func save() {
        guard validationMessage == nil else {
            didSave = false
            return
        }

        preferences.connectionMode = mode
        preferences.directHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.directPort = Int(portText) ?? preferences.directPort
        didSave = true
    }
}

struct GitPlaceholderView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GHSpacing.lg) {
                Text("Git")
                    .font(GHTypography.titleLg)
                    .foregroundStyle(GHColors.textPrimary)

                GHBanner(
                    tone: .neutral,
                    title: "Not Yet Implemented",
                    message: "Git tooling lands in a later task. This tab is a safe placeholder only."
                )
            }
            .padding(GHSpacing.xl)
        }
        .background(GHColors.bgPrimary)
    }
}

struct FilesPlaceholderView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GHSpacing.lg) {
                Text("Files")
                    .font(GHTypography.titleLg)
                    .foregroundStyle(GHColors.textPrimary)

                GHBanner(
                    tone: .neutral,
                    title: "Not Yet Implemented",
                    message: "The file browser arrives in a later task. This tab remains a placeholder."
                )
            }
            .padding(GHSpacing.xl)
        }
        .background(GHColors.bgPrimary)
    }
}

private extension Mrt_ApprovalType {
    var displayName: String {
        switch self {
        case .fileWrite:
            return "File Write"
        case .shellCommand:
            return "Shell Command"
        case .networkAccess:
            return "Network"
        case .unspecified, .UNRECOGNIZED:
            return "Approval"
        }
    }
}

private extension Mrt_TaskStatus {
    var displayName: String {
        switch self {
        case .idle:
            return "Idle"
        case .running:
            return "Running"
        case .waitingApproval:
            return "Needs Approval"
        case .completed:
            return "Completed"
        case .error:
            return "Error"
        case .cancelled:
            return "Cancelled"
        case .unspecified, .UNRECOGNIZED:
            return "Unknown"
        }
    }
}

struct FeatureChatMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
        case system
    }

    let id: UUID
    let sessionID: String?
    var content: String
    var isComplete: Bool
    let role: Role
    let timestamp: Date

    init(
        id: UUID = UUID(),
        sessionID: String?,
        content: String,
        isComplete: Bool,
        role: Role,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.content = content
        self.isComplete = isComplete
        self.role = role
        self.timestamp = timestamp
    }

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
