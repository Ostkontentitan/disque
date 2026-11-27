import SwiftUI

/// Colors resolve per appearance: the window follows the system's light/dark setting, and a view
/// can pin one with `.environment(\.colorScheme, …)` (e.g. controls drawn over artwork).
enum Theme {
    static let background = Color.adaptive(light: .rgb(1, 1, 1), dark: .rgb(0.071, 0.071, 0.078))
    static let sidebar = Color.adaptive(light: .rgb(0.957, 0.957, 0.965), dark: .rgb(0.035, 0.035, 0.04))
    static let elevated = Color.adaptive(light: .rgb(0.98, 0.98, 0.985), dark: .rgb(0.105, 0.105, 0.115))
    static let playerBar = Color.adaptive(light: .rgb(0.973, 0.973, 0.978), dark: .rgb(0.055, 0.055, 0.062))
    static let hover = Color.adaptive(light: .black(0.045), dark: .white(0.06))
    static let selected = Color.adaptive(light: .black(0.075), dark: .white(0.1))
    static let separator = Color.adaptive(light: .black(0.09), dark: .white(0.08))
    static let field = Color.adaptive(light: .black(0.055), dark: .white(0.08))
    static let fieldFocused = Color.adaptive(light: .black(0.075), dark: .white(0.12))
    static let fieldFocusRing = Color.adaptive(light: .black(0.2), dark: .white(0.25))
    /// Fill of round icon buttons and secondary pills.
    static let control = Color.adaptive(light: .black(0.06), dark: .white(0.08))
    static let controlHover = Color.adaptive(light: .black(0.1), dark: .white(0.15))
    static let border = Color.adaptive(light: .black(0.18), dark: .white(0.18))
    static let sliderTrack = Color.adaptive(light: .black(0.13), dark: .white(0.16))
    static let sliderFill = Color.adaptive(light: .black(0.55), dark: .white(0.85))
    static let primaryText = Color.adaptive(light: .rgb(0.075, 0.075, 0.085), dark: .white(1))
    static let secondaryText = Color.adaptive(light: .black(0.6), dark: .white(0.62))
    static let tertiaryText = Color.adaptive(light: .black(0.42), dark: .white(0.38))
    /// Slightly deeper in light mode so accent-colored text keeps its contrast on white.
    static let accent = Color.adaptive(light: .rgb(0.1, 0.45, 0.95), dark: .rgb(0.24, 0.55, 1.0))
    /// The app mark: a white record on dark chrome, a black one on light chrome.
    static let vinylDisc = Color.adaptive(light: .rgb(0.12, 0.12, 0.13), dark: .white(0.96))
    static let vinylGroove = Color.adaptive(light: .white(0.14), dark: .black(0.1))

    /// Drop shadows: light surfaces need a much softer shadow than dark ones for the same depth.
    static func shadow(_ opacity: Double) -> Color {
        Color.adaptive(light: .black(opacity * 0.45), dark: .black(opacity))
    }

    static let pagePadding: CGFloat = 36
    /// Left/right inset of sidebar and player bar content.
    static let chromePadding: CGFloat = 24
    static let heroTitleSize: CGFloat = 42
    static let heroArtworkSize: CGFloat = 256

    /// Stays dark in both appearances: it stands in for a cover, and its glyphs are white.
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

extension Color {
    /// A color that resolves against the effective appearance of the view drawing it.
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

private extension NSColor {
    static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    static func white(_ alpha: CGFloat) -> NSColor { NSColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha) }
    static func black(_ alpha: CGFloat) -> NSColor { NSColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha) }
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
