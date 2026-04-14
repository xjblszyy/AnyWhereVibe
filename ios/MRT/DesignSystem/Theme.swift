import SwiftUI

enum GHColors {
    static let bgPrimary = Color(hex: "0D1117")
    static let bgSecondary = Color(hex: "161B22")
    static let bgTertiary = Color(hex: "21262D")
    static let bgOverlay = Color(hex: "30363D")

    static let borderDefault = Color(hex: "30363D")
    static let borderMuted = Color(hex: "21262D")

    static let textPrimary = Color(hex: "E6EDF3")
    static let textSecondary = Color(hex: "8B949E")
    static let textTertiary = Color(hex: "6E7681")

    static let accentBlue = Color(hex: "58A6FF")
    static let accentGreen = Color(hex: "3FB950")
    static let accentRed = Color(hex: "F85149")
    static let accentYellow = Color(hex: "D29922")
    static let accentPurple = Color(hex: "BC8CFF")
    static let accentOrange = Color(hex: "F0883E")
}

enum GHTypography {
    static let titleLg = Font.system(size: 24, weight: .bold)
    static let title = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 15)
    static let bodySm = Font.system(size: 13)
    static let caption = Font.system(size: 12)
    static let code = Font.system(size: 13, design: .monospaced)
    static let codeSm = Font.system(size: 11, design: .monospaced)
}

enum GHSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

enum GHRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 12
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255

        self.init(red: red, green: green, blue: blue)
    }
}
