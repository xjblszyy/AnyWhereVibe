import SwiftUI

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
