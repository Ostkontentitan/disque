import Foundation

/// A single audio file in the library, with its normalised metadata.
struct Track: Identifiable, Hashable, Codable, Sendable {
    let path: String
    var title: String
    var artist: String
    var albumArtist: String?
    var album: String
    var trackNumber: Int?
    var trackTotal: Int?
    var discNumber: Int?
    var discTotal: Int?
    var year: Int?
    var genre: String?
    var composer: String?
    var isCompilation: Bool
    var duration: Double
    var bitrate: Int?
    var sampleRate: Int?
    var channels: Int?
    var isVBR: Bool
    var hasEmbeddedArtwork: Bool
    var fileSize: Int64
    var modificationDate: Date
    var dateAdded: Date

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var fileName: String { (path as NSString).lastPathComponent }
    var directory: String { (path as NSString).deletingLastPathComponent }
    var format: String { (path as NSString).pathExtension.uppercased() }

    var qualityLabel: String {
        var parts = [format]
        if let bitrate {
            parts.append(isVBR ? "VBR \(bitrate) kbps" : "\(bitrate) kbps")
        }
        if let sampleRate {
            parts.append(Formatters.sampleRate(sampleRate))
        }
        return parts.joined(separator: " · ")
    }
}
