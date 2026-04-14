import SwiftUI

struct GHTabItem<Value: Hashable>: Identifiable {
    let id: Value
    let title: String
    let systemImage: String
    let badge: String?

    init(id: Value, title: String, systemImage: String, badge: String? = nil) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.badge = badge
    }
}

struct GHTabBar<Value: Hashable>: View {
    let items: [GHTabItem<Value>]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: GHSpacing.sm) {
            ForEach(items) { item in
                Button {
                    selection = item.id
                } label: {
                    VStack(spacing: GHSpacing.xs) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: item.systemImage)
                                .font(.system(size: 15, weight: .semibold))

                            if let badge = item.badge {
                                Text(badge)
                                    .font(GHTypography.codeSm)
                                    .foregroundStyle(GHColors.textPrimary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(GHColors.accentRed)
                                    .clipShape(Capsule())
                                    .offset(x: 10, y: -8)
                            }
                        }

                        Text(item.title)
                            .font(GHTypography.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, GHSpacing.sm)
                    .foregroundStyle(selection == item.id ? GHColors.textPrimary : GHColors.textSecondary)
                    .background(selection == item.id ? GHColors.bgTertiary : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: GHRadius.md))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, GHSpacing.md)
        .padding(.top, GHSpacing.sm)
        .padding(.bottom, GHSpacing.md)
        .background(GHColors.bgSecondary)
    }
}

#Preview {
    @Previewable @State var selection = 0

    return ZStack(alignment: .bottom) {
        GHColors.bgPrimary.ignoresSafeArea()
        GHTabBar(
            items: [
                GHTabItem(id: 0, title: "Chat", systemImage: "bubble.left"),
                GHTabItem(id: 1, title: "Settings", systemImage: "gearshape", badge: "1"),
            ],
            selection: $selection
        )
    }
}
