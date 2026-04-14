import SwiftUI

struct FilesPlaceholderView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GHSpacing.lg) {
                Text("Files")
                    .font(GHTypography.titleLg)
                    .foregroundStyle(GHColors.textPrimary)

                GHBanner(
                    tone: .neutral,
                    title: "Not Yet Implemented",
                    message: "The file browser arrives in a later task. This tab remains a placeholder."
                )
            }
            .padding(GHSpacing.xl)
        }
        .background(GHColors.bgPrimary)
    }
}
