import SwiftUI

struct GHBanner: View {
    enum Tone {
        case info
        case success
        case warning
        case error
        case neutral
    }

    let tone: Tone
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: GHSpacing.md) {
            Image(systemName: iconName)
                .foregroundStyle(accentColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: GHSpacing.xs) {
                Text(title)
                    .font(GHTypography.bodySm)
                    .fontWeight(.semibold)
                    .foregroundStyle(GHColors.textPrimary)

                Text(message)
                    .font(GHTypography.bodySm)
                    .foregroundStyle(GHColors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(GHSpacing.md)
        .background(GHColors.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: GHRadius.md)
                .stroke(accentColor.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: GHRadius.md))
    }

    private var accentColor: Color {
        switch tone {
        case .info:
            return GHColors.accentBlue
        case .success:
            return GHColors.accentGreen
        case .warning:
            return GHColors.accentYellow
        case .error:
            return GHColors.accentRed
        case .neutral:
            return GHColors.textSecondary
        }
    }

    private var iconName: String {
        switch tone {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        case .neutral:
            return "circle.grid.2x2.fill"
        }
    }
}

#Preview {
    ZStack {
        GHColors.bgPrimary.ignoresSafeArea()
        GHBanner(tone: .warning, title: "Needs Approval", message: "Later tasks will render live approval requests here.")
            .padding()
    }
}
