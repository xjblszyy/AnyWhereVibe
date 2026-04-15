import SwiftUI

struct SessionSidebarView: View {
    @ObservedObject var viewModel: SessionViewModel
    let connectionState: ConnectionState

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
                .opacity(isCreateDisabled ? 0.5 : 1)
                .disabled(isCreateDisabled)
            }
            .padding(.horizontal, GHSpacing.lg)

            if !viewModel.canCreateSession(connectionState: connectionState) {
                Text("Session creation is available once the agent is connected.")
                    .font(GHTypography.caption)
                    .foregroundStyle(GHColors.textSecondary)
                    .padding(.horizontal, GHSpacing.lg)
            }

            ScrollView {
                LazyVStack(spacing: GHSpacing.sm) {
                    ForEach(viewModel.sessions) { session in
                        SessionRowView(
                            session: session,
                            isActive: session.id == viewModel.activeSessionID,
                            onSelect: { viewModel.selectSession(id: session.id) },
                            onCancel: { viewModel.cancelTask(id: session.id) },
                            onClose: { viewModel.closeSession(id: session.id) }
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

    private var isCreateDisabled: Bool {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !viewModel.canCreateSession(connectionState: connectionState)
    }
}
