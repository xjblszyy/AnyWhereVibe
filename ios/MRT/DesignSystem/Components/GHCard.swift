import SwiftUI

struct GHCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: GHSpacing.md) {
            content
        }
        .padding(GHSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GHColors.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: GHRadius.lg)
                .stroke(GHColors.borderDefault, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: GHRadius.lg))
    }
}

#Preview {
    ZStack {
        GHColors.bgPrimary.ignoresSafeArea()
        GHCard {
            Text("Preview Card")
                .foregroundStyle(GHColors.textPrimary)
        }
        .padding()
    }
}
