import SwiftUI
import WatchKit

struct ApprovalView: View {
    let request: ApprovalInfo
    let onRespond: (Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: WatchSpacing.md) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title3)
                    .foregroundStyle(WatchGH.accentYellow)

                Text(request.title)
                    .font(WatchGH.title)
                    .foregroundStyle(WatchGH.textPrimary)
                    .multilineTextAlignment(.center)

                Text(request.description)
                    .font(WatchGH.caption)
                    .foregroundStyle(WatchGH.textSecondary)
                    .multilineTextAlignment(.center)

                if !request.command.isEmpty {
                    Text(request.command)
                        .font(WatchGH.code)
                        .foregroundStyle(WatchGH.textPrimary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(WatchSpacing.sm)
                        .background(WatchGH.bgTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: WatchRadius.chip))
                }

                HStack(spacing: WatchSpacing.lg) {
                    Button(action: { onRespond(false) }) {
                        Image(systemName: "xmark")
                            .foregroundStyle(WatchGH.accentRed)
                            .frame(width: 44, height: 44)
                            .background(WatchGH.accentRed.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Button(action: { onRespond(true) }) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(WatchGH.accentGreen)
                            .frame(width: 44, height: 44)
                            .background(WatchGH.accentGreen.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(WatchSpacing.sm)
        }
        .onAppear {
            WKInterfaceDevice.current().play(.notification)
        }
    }
}
