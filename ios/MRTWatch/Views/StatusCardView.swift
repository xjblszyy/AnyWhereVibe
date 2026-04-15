import SwiftUI

struct StatusCardView: View {
    let state: WatchState

    var body: some View {
        VStack(alignment: .leading, spacing: WatchSpacing.sm) {
            HStack(spacing: WatchSpacing.xs) {
                Circle()
                    .fill(state.isConnected ? WatchGH.accentGreen : WatchGH.textTertiary)
                    .frame(width: 6, height: 6)

                Text(state.isConnected ? "Connected" : "Offline")
                    .font(WatchGH.caption)
                    .foregroundStyle(WatchGH.textTertiary)

                Spacer()
            }

            if let session = state.activeSession {
                Text(session.name)
                    .font(WatchGH.title)
                    .foregroundStyle(WatchGH.textPrimary)
                    .lineLimit(1)

                HStack(spacing: WatchSpacing.sm) {
                    Image(systemName: session.status.iconName)
                        .font(.system(size: 12))
                        .foregroundStyle(session.status.color)

                    Text(session.status.displayText)
                        .font(WatchGH.body)
                        .foregroundStyle(session.status.color)
                        .lineLimit(1)
                }

                if let summary = session.lastSummary ?? state.lastSummary {
                    Text(summary)
                        .font(WatchGH.caption)
                        .foregroundStyle(WatchGH.textSecondary)
                        .lineLimit(2)
                }
            } else {
                Text("No active task")
                    .font(WatchGH.body)
                    .foregroundStyle(WatchGH.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WatchSpacing.md)
        .background(WatchGH.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: WatchRadius.card)
                .stroke(WatchGH.borderDefault, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: WatchRadius.card))
    }
}
