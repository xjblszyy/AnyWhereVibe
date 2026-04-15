import SwiftUI

enum WatchGH {
    static let bgPrimary = Color(hex: "0d1117")
    static let bgSecondary = Color(hex: "161b22")
    static let bgTertiary = Color(hex: "21262d")
    static let borderDefault = Color(hex: "30363d")

    static let textPrimary = Color(hex: "e6edf3")
    static let textSecondary = Color(hex: "8b949e")
    static let textTertiary = Color(hex: "6e7681")

    static let accentBlue = Color(hex: "58a6ff")
    static let accentGreen = Color(hex: "3fb950")
    static let accentRed = Color(hex: "f85149")
    static let accentYellow = Color(hex: "d29922")
    static let accentPurple = Color(hex: "bc8cff")
    static let accentOrange = Color(hex: "f0883e")

    static let title = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 14)
    static let caption = Font.system(size: 12)
    static let code = Font.system(size: 11, design: .monospaced)
}

enum WatchSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 10
    static let lg: CGFloat = 12
}

enum WatchRadius {
    static let card: CGFloat = 12
    static let chip: CGFloat = 8
    static let pill: CGFloat = 22
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
