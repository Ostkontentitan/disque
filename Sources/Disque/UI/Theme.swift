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
    /// Left/right inset of sidebar and player bar content.
    static let chromePadding: CGFloat = 24
    static let heroTitleSize: CGFloat = 42
    static let heroArtworkSize: CGFloat = 256

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

/// Font pairings the app can be set in (Settings → Appearance). `display` is used for page and
/// section titles, `text` for everything else; SF Symbols always stay in the system font.
enum Typeface: String, CaseIterable, Identifiable {
    case system, rounded, editorial, avenir, futura

    static let storageKey = "appearance.typeface"

    /// Read straight from defaults so every view sees the same value during a re-render.
    static var current: Typeface {
        UserDefaults.standard.string(forKey: storageKey).flatMap(Typeface.init(rawValue:)) ?? .system
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "SF Pro"
        case .rounded: "SF Pro Rounded"
        case .editorial: "New York + SF Pro"
        case .avenir: "Avenir Next"
        case .futura: "Futura + SF Pro"
        }
    }

    var summary: String {
        switch self {
        case .system: "Neutral and native. The macOS default."
        case .rounded: "Softer and friendlier; matches the wordmark."
        case .editorial: "Serif titles over a sans interface, like a liner-notes booklet."
        case .avenir: "Geometric and warm, a classic music-app look."
        case .futura: "Mid-century jazz-sleeve titles over a sans interface."
        }
    }

    func text(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        switch self {
        case .system, .editorial, .futura: .system(size: size, weight: weight)
        case .rounded: .system(size: size, weight: weight, design: .rounded)
        case .avenir: .custom("Avenir Next", fixedSize: size).weight(weight)
        }
    }

    func display(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        switch self {
        case .system, .rounded: text(size, weight)
        // Avenir Next Heavy is too blocky at title sizes; Bold carries the same emphasis.
        case .avenir: text(size, weight == .heavy || weight == .black ? .bold : weight)
        case .editorial: .system(size: size, weight: weight, design: .serif)
        case .futura: .custom("Futura", fixedSize: size).weight(weight)
        }
    }
}

extension Font {
    /// Interface text: labels, rows, metadata.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Typeface.current.text(size, weight)
    }

    /// Page, hero and section titles.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        Typeface.current.display(size, weight)
    }
}
