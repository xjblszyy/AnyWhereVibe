import SwiftUI

struct OfflineView: View {
    var body: some View {
        VStack(spacing: WatchSpacing.md) {
            Image(systemName: "iphone.slash")
                .font(.title2)
                .foregroundStyle(WatchGH.textTertiary)

            Text("Waiting for iPhone")
                .font(WatchGH.title)
                .foregroundStyle(WatchGH.textPrimary)
                .multilineTextAlignment(.center)

            Text("Open the iPhone app to activate WatchConnectivity.")
                .font(WatchGH.caption)
                .foregroundStyle(WatchGH.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(WatchSpacing.lg)
        .background(WatchGH.bgPrimary)
    }
}
