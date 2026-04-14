import SwiftUI

struct GHCodeBlock: View {
    let code: String
    let language: String?

    var body: some View {
        VStack(alignment: .leading, spacing: GHSpacing.sm) {
            if let language, !language.isEmpty {
                Text(language.uppercased())
                    .font(GHTypography.codeSm)
                    .foregroundStyle(GHColors.textTertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(GHTypography.code)
                    .foregroundStyle(GHColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(GHSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GHColors.bgTertiary)
        .overlay(
            RoundedRectangle(cornerRadius: GHRadius.md)
                .stroke(GHColors.borderDefault, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: GHRadius.md))
    }
}

#Preview {
    ZStack {
        GHColors.bgPrimary.ignoresSafeArea()
        GHCodeBlock(code: "let value = 42", language: "swift")
            .padding()
    }
}
