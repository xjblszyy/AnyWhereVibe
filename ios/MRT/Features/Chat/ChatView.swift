import SwiftUI

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
                    .onChange(of: viewModel.lastMessageSignature) { _, _ in
                        guard let lastID = viewModel.messages.last?.id else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }

                if let request = viewModel.pendingApproval {
                    ApprovalBannerView(
                        request: request,
                        onApprove: { Task { await viewModel.respondToApproval(true) } },
                        onReject: { Task { await viewModel.respondToApproval(false) } }
                    )
                    .padding(.horizontal, GHSpacing.lg)
                    .padding(.bottom, GHSpacing.md)
                }

                PromptInputBar(
                    text: $viewModel.inputText,
                    isLoading: viewModel.isLoading,
                    placeholder: viewModel.activeSessionID == nil ? "Select or create a session to start chatting" : "Send a prompt to the active session",
                    message: viewModel.activeSessionID == nil ? "Select or create a session first." : nil,
                    isDisabled: viewModel.activeSessionID == nil || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
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

                SessionSidebarView(viewModel: sessionViewModel, connectionState: viewModel.connectionState)
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
