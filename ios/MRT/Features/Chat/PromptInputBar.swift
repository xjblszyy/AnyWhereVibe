import SwiftUI

struct PromptInputBar: View {
    @Binding var text: String
    let isDisabled: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: GHSpacing.sm) {
            GHInput(title: nil, text: $text, placeholder: "Send a prompt to the active session")
            GHButton(title: "Send", icon: "paperplane.fill", style: .primary, action: onSend)
                .opacity(isDisabled ? 0.5 : 1)
                .disabled(isDisabled)
        }
        .padding(GHSpacing.lg)
        .background(GHColors.bgSecondary)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(GHColors.borderMuted)
                .frame(height: 1)
        }
    }
}
