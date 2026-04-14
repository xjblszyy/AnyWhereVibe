import SwiftUI

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
