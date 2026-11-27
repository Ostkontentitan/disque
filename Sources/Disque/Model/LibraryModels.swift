import Foundation

/// Describes where artwork for an album can be found. Used as the cache key for the artwork loader.
struct ArtworkRequest: Hashable, Sendable {
    let key: String
    let embeddedPath: String?
    let directory: String
    let seed: String
}

struct Album: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let artist: String
    let artistID: String
    let year: Int?
    let genre: String?
    let tracks: [Track]
    let duration: Double
    let dateAdded: Date
    let directory: String
    let discCount: Int
    let isCompilation: Bool
    let artwork: ArtworkRequest
    let sortTitle: String
    let sortArtist: String

    var totalSize: Int64 { tracks.reduce(0) { $0 + $1.fileSize } }

    var qualityLabel: String {
        guard let first = tracks.first else { return "" }
        let formats = Set(tracks.map(\.format))
        guard formats.count == 1 else { return formats.sorted().joined(separator: " / ") }
        var parts = [first.format]
        let bitrates = tracks.compactMap(\.bitrate)
        if tracks.contains(where: \.isVBR), !bitrates.isEmpty {
            parts.append("VBR ~\(bitrates.reduce(0, +) / bitrates.count) kbps")
        } else if Set(bitrates).count == 1, let bitrate = bitrates.first {
            parts.append("\(bitrate) kbps")
        }
        if let rate = first.sampleRate {
            parts.append(Formatters.sampleRate(rate))
        }
        return parts.joined(separator: " · ")
    }

    var shortQuality: String {
        guard let first = tracks.first else { return "" }
        if tracks.contains(where: \.isVBR) { return "\(first.format) VBR" }
        let bitrates = Set(tracks.compactMap(\.bitrate))
        if bitrates.count == 1, let bitrate = bitrates.first, first.format == "MP3" || first.format == "M4A" || first.format == "AAC" {
            return "\(first.format) \(bitrate)"
        }
        return first.format
    }
}

struct Artist: Identifiable, Sendable {
    let id: String
    let name: String
    /// Albums where this artist is the album artist, newest first.
    let albums: [Album]
    /// Albums by other artists (or compilations) that contain tracks by this artist.
    let appearsOn: [Album]
    let tracks: [Track]

    var artwork: ArtworkRequest? { (albums.first ?? appearsOn.first)?.artwork }

    static func makeID(_ name: String) -> String { name.searchKey.trimmed }
}

struct Genre: Identifiable, Sendable {
    let id: String
    let name: String
    let albums: [Album]

    var trackCount: Int { albums.reduce(0) { $0 + $1.tracks.count } }
}

struct Playlist: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var trackPaths: [String]
    var created: Date
    var modified: Date
}

struct HistoryEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var path: String
    var date: Date
}
