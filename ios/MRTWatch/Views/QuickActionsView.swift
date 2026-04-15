import SwiftUI

struct QuickActionsView: View {
    let selectedSessionID: String?
    let onAction: (String) -> Void

    var body: some View {
        List {
            quickActionButton(title: "Continue", systemImage: "play.fill", color: WatchGH.accentGreen, action: "continue")
            quickActionButton(title: "Cancel", systemImage: "stop.fill", color: WatchGH.accentRed, action: "cancel")
            quickActionButton(title: "Retry", systemImage: "arrow.clockwise", color: WatchGH.accentBlue, action: "retry")
        }
        .listStyle(.carousel)
    }

    @ViewBuilder
    private func quickActionButton(title: String, systemImage: String, color: Color, action: String) -> some View {
        Button {
            onAction(action)
        } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(color)
        }
        .disabled(selectedSessionID == nil)
    }
}
