import SwiftUI

struct GHList<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: GHSpacing.sm) {
            if let title {
                Text(title)
                    .font(GHTypography.caption)
                    .foregroundStyle(GHColors.textTertiary)
                    .textCase(.uppercase)
            }

            VStack(spacing: 0) {
                content
            }
            .background(GHColors.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: GHRadius.lg)
                    .stroke(GHColors.borderDefault, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: GHRadius.lg))
        }
    }
}

struct GHListRow: View {
    let title: String
    let subtitle: String?
    let trailing: AnyView?

    init(title: String, subtitle: String? = nil, trailing: AnyView? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: GHSpacing.md) {
            VStack(alignment: .leading, spacing: GHSpacing.xs) {
                Text(title)
                    .font(GHTypography.bodySm)
                    .foregroundStyle(GHColors.textPrimary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(GHTypography.caption)
                        .foregroundStyle(GHColors.textSecondary)
                }
            }

            Spacer()

            if let trailing {
                trailing
            }
        }
        .padding(.horizontal, GHSpacing.md)
        .padding(.vertical, GHSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GHColors.bgSecondary)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(GHColors.borderMuted)
                .frame(height: 1)
        }
    }
}

#Preview {
    ZStack {
        GHColors.bgPrimary.ignoresSafeArea()
        GHList(title: "Sessions") {
            GHListRow(title: "Session One", subtitle: "Online", trailing: AnyView(GHBadge(text: "Live", color: GHColors.accentGreen)))
            GHListRow(title: "Session Two", subtitle: "Idle")
        }
        .padding()
    }
}
