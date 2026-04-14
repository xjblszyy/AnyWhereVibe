import SwiftUI

struct GHBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(GHTypography.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, GHSpacing.sm)
            .padding(.vertical, GHSpacing.xs)
            .foregroundStyle(color)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

#Preview {
    ZStack {
        GHColors.bgPrimary.ignoresSafeArea()
        GHBadge(text: "Online", color: GHColors.accentGreen)
    }
}
