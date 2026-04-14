import SwiftUI

struct GHInput: View {
    let title: String?
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: GHSpacing.sm) {
            if let title {
                Text(title)
                    .font(GHTypography.bodySm)
                    .foregroundStyle(GHColors.textSecondary)
            }

            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(GHTypography.body)
                .foregroundStyle(GHColors.textPrimary)
                .padding(GHSpacing.md)
                .background(GHColors.bgPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: GHRadius.md)
                        .stroke(GHColors.borderDefault, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: GHRadius.md))
        }
    }
}

#Preview {
    @Previewable @State var value = ""

    return ZStack {
        GHColors.bgPrimary.ignoresSafeArea()
        GHInput(title: "Prompt", text: $value, placeholder: "Type a command")
            .padding()
    }
}
