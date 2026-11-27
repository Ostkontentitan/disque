import SwiftUI

enum Theme {
    static let background = Color(red: 0.071, green: 0.071, blue: 0.078)
    static let sidebar = Color(red: 0.035, green: 0.035, blue: 0.04)
    static let elevated = Color(red: 0.105, green: 0.105, blue: 0.115)
    static let playerBar = Color(red: 0.055, green: 0.055, blue: 0.062)
    static let hover = Color.white.opacity(0.06)
    static let selected = Color.white.opacity(0.1)
    static let separator = Color.white.opacity(0.08)
    static let field = Color.white.opacity(0.08)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.38)
    static let accent = Color(red: 0.24, green: 0.55, blue: 1.0)

    static let pagePadding: CGFloat = 36

    static func placeholderGradient(seed: String) -> LinearGradient {
        let hue = Double(seed.stableHash % 360) / 360
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.32, brightness: 0.34),
                Color(hue: (hue + 0.07).truncatingRemainder(dividingBy: 1), saturation: 0.42, brightness: 0.16),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func tileColor(seed: String) -> Color {
        let hue = Double(seed.stableHash % 360) / 360
        return Color(hue: hue, saturation: 0.55, brightness: 0.48)
    }
}

extension Font {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}
