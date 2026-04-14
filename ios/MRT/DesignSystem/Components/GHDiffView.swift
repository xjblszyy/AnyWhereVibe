import SwiftUI

struct GHDiffLine: Identifiable {
    enum Kind {
        case addition
        case deletion
        case context
    }

    let id = UUID()
    let kind: Kind
    let content: String
}

struct GHDiffView: View {
    let title: String
    let lines: [GHDiffLine]

    var body: some View {
        GHCard {
            Text(title)
                .font(GHTypography.bodySm)
                .foregroundStyle(GHColors.textSecondary)

            VStack(spacing: 0) {
                ForEach(lines) { line in
                    HStack(alignment: .top, spacing: GHSpacing.md) {
                        Rectangle()
                            .fill(gutterColor(for: line.kind))
                            .frame(width: 3)

                        Text(line.content)
                            .font(GHTypography.code)
                            .foregroundStyle(GHColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, GHSpacing.xs)
                    .padding(.horizontal, GHSpacing.sm)
                    .background(backgroundColor(for: line.kind))
                }
            }
            .background(GHColors.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: GHRadius.md))
        }
    }

    private func gutterColor(for kind: GHDiffLine.Kind) -> Color {
        switch kind {
        case .addition:
            return GHColors.accentGreen
        case .deletion:
            return GHColors.accentRed
        case .context:
            return GHColors.borderDefault
        }
    }

    private func backgroundColor(for kind: GHDiffLine.Kind) -> Color {
        switch kind {
        case .addition:
            return GHColors.accentGreen.opacity(0.08)
        case .deletion:
            return GHColors.accentRed.opacity(0.08)
        case .context:
            return GHColors.bgPrimary
        }
    }
}

#Preview {
    ZStack {
        GHColors.bgPrimary.ignoresSafeArea()
        GHDiffView(
            title: "Placeholder Diff",
            lines: [
                .init(kind: .context, content: "@@ -1,3 +1,3 @@"),
                .init(kind: .deletion, content: "- old line"),
                .init(kind: .addition, content: "+ new line"),
            ]
        )
        .padding()
    }
}
