import SwiftUI

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
