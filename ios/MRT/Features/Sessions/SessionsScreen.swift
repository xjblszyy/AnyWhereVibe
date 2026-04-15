import SwiftUI

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
                            onSelect: { viewModel.selectSession(id: session.id) },
                            onClose: { viewModel.closeSession(id: session.id) }
                        )
                    }
                }
            }
            .padding(GHSpacing.xl)
        }
        .background(GHColors.bgPrimary)
    }
}
