import SwiftUI

struct ApprovalBannerView: View {
    let request: Mrt_ApprovalRequest
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        GHCard {
            VStack(alignment: .leading, spacing: GHSpacing.md) {
                HStack {
                    Text("Permission Required")
                        .font(GHTypography.bodySm)
                        .fontWeight(.semibold)
                        .foregroundStyle(GHColors.accentYellow)
                    Spacer()
                    GHBadge(text: request.approvalType.displayName, color: GHColors.accentYellow)
                }

                Text(request.description_p)
                    .font(GHTypography.bodySm)
                    .foregroundStyle(GHColors.textSecondary)

                if !request.command.isEmpty {
                    GHCodeBlock(code: request.command, language: "bash")
                }

                HStack(spacing: GHSpacing.sm) {
                    GHButton(title: "Reject", icon: "xmark", style: .danger, action: onReject)
                    GHButton(title: "Approve", icon: "checkmark", style: .primary, action: onApprove)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: GHRadius.lg)
                .stroke(GHColors.accentYellow.opacity(0.45), lineWidth: 1)
        )
    }
}

private extension Mrt_ApprovalType {
    var displayName: String {
        switch self {
        case .fileWrite:
            return "File Write"
        case .shellCommand:
            return "Shell Command"
        case .networkAccess:
            return "Network"
        case .unspecified, .UNRECOGNIZED:
            return "Approval"
        }
    }
}
