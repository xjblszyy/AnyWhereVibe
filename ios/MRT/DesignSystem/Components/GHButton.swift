import SwiftUI

struct GHButton: View {
    enum Style {
        case primary
        case secondary
        case danger
    }

    let title: String
    let icon: String?
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: GHSpacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                }

                Text(title)
                    .font(GHTypography.bodySm)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, GHSpacing.md)
            .padding(.vertical, GHSpacing.sm)
            .frame(minHeight: 36)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: GHRadius.sm)
                    .stroke(borderColor, lineWidth: style == .secondary ? 1 : 0)
            )
            .clipShape(RoundedRectangle(cornerRadius: GHRadius.sm))
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:
            return GHColors.accentBlue.opacity(0.15)
        case .secondary:
            return GHColors.bgSecondary
        case .danger:
            return GHColors.accentRed.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            return GHColors.accentBlue
        case .secondary:
            return GHColors.textSecondary
        case .danger:
            return GHColors.accentRed
        }
    }

    private var borderColor: Color {
        style == .secondary ? GHColors.borderDefault : .clear
    }
}

#Preview {
    ZStack {
        GHColors.bgPrimary.ignoresSafeArea()
        HStack {
            GHButton(title: "Primary", icon: "paperplane.fill", style: .primary) {}
            GHButton(title: "Secondary", icon: nil, style: .secondary) {}
        }
        .padding()
    }
}
