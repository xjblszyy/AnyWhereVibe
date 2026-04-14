import SwiftUI

struct GitPlaceholderView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GHSpacing.lg) {
                Text("Git")
                    .font(GHTypography.titleLg)
                    .foregroundStyle(GHColors.textPrimary)

                GHBanner(
                    tone: .neutral,
                    title: "Not Yet Implemented",
                    message: "Git tooling lands in a later task. This tab is a safe placeholder only."
                )
            }
            .padding(GHSpacing.xl)
        }
        .background(GHColors.bgPrimary)
    }
}
