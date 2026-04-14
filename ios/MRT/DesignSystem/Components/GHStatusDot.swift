import SwiftUI

struct GHStatusDot: View {
    enum Status {
        case online
        case pending
        case error
        case offline
    }

    let status: Status

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch status {
        case .online:
            return GHColors.accentGreen
        case .pending:
            return GHColors.accentYellow
        case .error:
            return GHColors.accentRed
        case .offline:
            return GHColors.textTertiary
        }
    }
}

#Preview {
    ZStack {
        GHColors.bgPrimary.ignoresSafeArea()
        HStack {
            GHStatusDot(status: .online)
            GHStatusDot(status: .pending)
            GHStatusDot(status: .error)
            GHStatusDot(status: .offline)
        }
    }
}
