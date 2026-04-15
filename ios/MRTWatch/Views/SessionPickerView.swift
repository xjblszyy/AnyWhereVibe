import SwiftUI

struct SessionPickerView: View {
    let sessions: [SessionSummary]
    @Binding var selectedSessionID: String?
    let onSelect: (String) -> Void

    var body: some View {
        List {
            if sessions.isEmpty {
                Text("No sessions yet")
                    .font(WatchGH.caption)
                    .foregroundStyle(WatchGH.textSecondary)
            } else {
                ForEach(sessions) { session in
                    Button {
                        selectedSessionID = session.id
                        onSelect(session.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: WatchSpacing.xs) {
                                Text(session.name)
                                    .font(WatchGH.body)
                                    .foregroundStyle(WatchGH.textPrimary)
                                    .lineLimit(1)

                                Text(session.status.displayText)
                                    .font(WatchGH.caption)
                                    .foregroundStyle(session.status.color)
                            }

                            Spacer()

                            if selectedSessionID == session.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(WatchGH.accentBlue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.carousel)
    }
}
