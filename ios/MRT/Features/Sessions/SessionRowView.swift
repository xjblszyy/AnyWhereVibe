import SwiftUI

struct SessionRowView: View {
    let session: SessionModel
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: GHSpacing.md) {
                VStack(alignment: .leading, spacing: GHSpacing.xs) {
                    Text(session.name)
                        .font(GHTypography.bodySm)
                        .foregroundStyle(GHColors.textPrimary)

                    Text(session.workingDirectory)
                        .font(GHTypography.caption)
                        .foregroundStyle(GHColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                GHBadge(text: session.status.displayName, color: isActive ? GHColors.accentBlue : GHColors.textTertiary)
            }
            .padding(GHSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? GHColors.bgTertiary : GHColors.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: GHRadius.md)
                    .stroke(isActive ? GHColors.accentBlue.opacity(0.35) : GHColors.borderDefault, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: GHRadius.md))
        }
        .buttonStyle(.plain)
    }
}

private extension Mrt_TaskStatus {
    var displayName: String {
        switch self {
        case .idle:
            return "Idle"
        case .running:
            return "Running"
        case .waitingApproval:
            return "Needs Approval"
        case .completed:
            return "Completed"
        case .error:
            return "Error"
        case .cancelled:
            return "Cancelled"
        case .unspecified, .UNRECOGNIZED:
            return "Unknown"
        }
    }
}
