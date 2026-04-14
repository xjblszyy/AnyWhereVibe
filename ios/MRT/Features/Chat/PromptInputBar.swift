import SwiftUI

struct PromptInputBar: View {
    @Binding var text: String
    let isLoading: Bool
    let placeholder: String
    let message: String?
    let isDisabled: Bool
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GHSpacing.xs) {
            HStack(alignment: .bottom, spacing: GHSpacing.sm) {
                GHInput(title: nil, text: $text, placeholder: placeholder)
                GHButton(title: isLoading ? "Sending" : "Send", icon: "paperplane.fill", style: .primary, action: onSend)
                    .opacity(isSendDisabled ? 0.5 : 1)
                    .disabled(isSendDisabled)
            }

            if let message {
                Text(message)
                    .font(GHTypography.caption)
                    .foregroundStyle(GHColors.textSecondary)
            }
        }
        .padding(GHSpacing.lg)
        .background(GHColors.bgSecondary)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(GHColors.borderMuted)
                .frame(height: 1)
        }
    }

    private var isSendDisabled: Bool {
        isDisabled || isLoading
    }
}
