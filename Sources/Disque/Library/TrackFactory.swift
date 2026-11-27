import Foundation

/// Turns raw tag data into a `Track`, filling gaps from file and folder names.
enum TrackFactory {
    private static let fileNamePattern = try! NSRegularExpression(
        pattern: #"^(?:(\d{1,2})[-.])?(\d{1,3})[\s._-]+(?:-\s*)?(.+)$"#
    )
    private static let yearPrefixPattern = try! NSRegularExpression(pattern: #"^\(?(\d{4})\)?\s*[-–]?\s*(.+)$"#)

    static func make(path: String, meta: RawMetadata, fileSize: Int64, modified: Date, dateAdded: Date) -> Track {
        let url = URL(fileURLWithPath: path)
        let baseName = url.deletingPathExtension().lastPathComponent
        var folder = url.deletingLastPathComponent()
        if LibraryIndex.isDiscFolder(folder.lastPathComponent) { folder = folder.deletingLastPathComponent() }
        let folderInfo = parseFolderName(folder.lastPathComponent)
        let fileInfo = parseFileName(baseName)

        let artist = meta.artist.nonEmpty ?? meta.albumArtist.nonEmpty ?? folderInfo.artist ?? "Unknown Artist"
        let album = meta.album.nonEmpty ?? folderInfo.album.nilIfEmpty ?? "Unknown Album"

        return Track(
            path: path,
            title: meta.title.nonEmpty ?? fileInfo.title,
            artist: artist,
            albumArtist: meta.albumArtist.nonEmpty ?? (meta.isCompilation ? "Various Artists" : nil),
            album: album,
            trackNumber: meta.trackNumber ?? fileInfo.number,
            trackTotal: meta.trackTotal,
            discNumber: meta.discNumber ?? fileInfo.disc,
            discTotal: meta.discTotal,
            year: meta.year ?? folderInfo.year,
            genre: meta.genre.nonEmpty,
            composer: meta.composer.nonEmpty,
            isCompilation: meta.isCompilation,
            duration: max(0, meta.duration ?? 0),
            bitrate: meta.bitrate,
            sampleRate: meta.sampleRate,
            channels: meta.channels,
            isVBR: meta.isVBR,
            hasEmbeddedArtwork: meta.hasArtwork,
            fileSize: fileSize,
            modificationDate: modified,
            dateAdded: dateAdded
        )
    }

    static func parseFileName(_ name: String) -> (disc: Int?, number: Int?, title: String) {
        let range = NSRange(name.startIndex..., in: name)
        guard let match = fileNamePattern.firstMatch(in: name, range: range),
              let numberRange = Range(match.range(at: 2), in: name),
              let titleRange = Range(match.range(at: 3), in: name) else {
            return (nil, nil, name)
        }
        let disc = Range(match.range(at: 1), in: name).flatMap { Int(name[$0]) }
        let title = String(name[titleRange]).trimmed
        return (disc, Int(name[numberRange]), title.isEmpty ? name : title)
    }

    static func parseFolderName(_ name: String) -> (artist: String?, album: String, year: Int?) {
        var album = name
        var artist: String?
        var year: Int?
        if let separator = name.range(of: " - ") {
            let left = String(name[..<separator.lowerBound]).trimmed
            let right = String(name[separator.upperBound...]).trimmed
            if let value = Int(left), (1000...2999).contains(value) {
                year = value
                album = right
            } else {
                artist = left.nilIfEmpty
                album = right
            }
        }
        let range = NSRange(album.startIndex..., in: album)
        if let match = yearPrefixPattern.firstMatch(in: album, range: range),
           let yearRange = Range(match.range(at: 1), in: album),
           let restRange = Range(match.range(at: 2), in: album),
           let value = Int(album[yearRange]), (1000...2999).contains(value) {
            year = year ?? value
            album = String(album[restRange]).trimmed
        }
        return (artist, album, year)
    }
}
