import Foundation

enum Formatters {
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func longDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0 min" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    static func sampleRate(_ hertz: Int) -> String {
        let khz = Double(hertz) / 1000
        if khz == khz.rounded() { return "\(Int(khz)) kHz" }
        return String(format: "%.1f kHz", khz)
    }

    static func fileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func count(_ value: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(value.formatted()) \(value == 1 ? singular : (plural ?? singular + "s"))"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static func relativeDate(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "Just now" }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var nilIfEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }

    /// Case, diacritic and width insensitive representation used for matching and identity.
    var searchKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Key used for alphabetical sorting (ignores a leading "The ").
    var sortKey: String {
        let key = searchKey.trimmed
        if key.hasPrefix("the ") { return String(key.dropFirst(4)) }
        return key
    }

    /// Stable (non-randomised) hash, used for deterministic placeholder colours.
    var stableHash: UInt64 {
        var hash: UInt64 = 5381
        for byte in utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return hash
    }

    var initials: String {
        let words = split(whereSeparator: { $0 == " " || $0 == "-" }).filter { $0.first?.isLetter == true || $0.first?.isNumber == true }
        let letters = words.prefix(2).compactMap { $0.first }.map { String($0).uppercased() }
        return letters.joined()
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? { self?.nilIfEmpty }
}

extension Sequence {
    func mostCommon<T: Hashable>(_ transform: (Element) -> T?) -> T? {
        var counts: [T: Int] = [:]
        for element in self {
            if let value = transform(element) { counts[value, default: 0] += 1 }
        }
        return counts.max { lhs, rhs in lhs.value < rhs.value }?.key
    }
}
