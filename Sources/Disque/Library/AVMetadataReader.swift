import AVFoundation
import Foundation

/// Fallback reader for non-MP3 formats (AAC/ALAC, FLAC, WAV, AIFF) using AVFoundation.
enum AVMetadataReader {
    static func read(url: URL) async -> RawMetadata {
        var meta = RawMetadata()
        let asset = AVURLAsset(url: url)

        if let duration = try? await asset.load(.duration), duration.isNumeric {
            meta.duration = duration.seconds
        }

        var items: [AVMetadataItem] = []
        if let common = try? await asset.load(.commonMetadata) { items += common }
        if let all = try? await asset.load(.metadata) { items += all }

        meta.title = await string(items, [.commonIdentifierTitle, .iTunesMetadataSongName, .quickTimeMetadataTitle])
        meta.artist = await string(items, [.commonIdentifierArtist, .iTunesMetadataArtist, .quickTimeMetadataArtist])
        meta.album = await string(items, [.commonIdentifierAlbumName, .iTunesMetadataAlbum, .quickTimeMetadataAlbum])
        meta.albumArtist = await string(items, [.iTunesMetadataAlbumArtist])
        meta.composer = await string(items, [.iTunesMetadataComposer, .quickTimeMetadataComposer])
        if let genre = await string(items, [.iTunesMetadataUserGenre, .quickTimeMetadataGenre]) {
            meta.genre = MetadataParsing.genre(genre)
        }
        if let date = await string(items, [.iTunesMetadataReleaseDate, .commonIdentifierCreationDate, .quickTimeMetadataYear]) {
            meta.year = MetadataParsing.year(date)
        }
        if let (number, total) = await numberPair(items, .iTunesMetadataTrackNumber) {
            meta.trackNumber = number
            meta.trackTotal = total
        }
        if let (number, total) = await numberPair(items, .iTunesMetadataDiscNumber) {
            meta.discNumber = number
            meta.discTotal = total
        }
        meta.hasArtwork = !AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork).isEmpty
            || !AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .iTunesMetadataCoverArt).isEmpty

        if let track = try? await asset.loadTracks(withMediaType: .audio).first {
            if let rate = try? await track.load(.estimatedDataRate), rate > 0 {
                meta.bitrate = Int((rate / 1000).rounded())
            }
            if let descriptions = try? await track.load(.formatDescriptions),
               let description = descriptions.first,
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
                meta.sampleRate = Int(asbd.mSampleRate)
                meta.channels = Int(asbd.mChannelsPerFrame)
            }
        }
        return meta
    }

    static func artwork(url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        var items: [AVMetadataItem] = []
        if let common = try? await asset.load(.commonMetadata) { items += common }
        if let all = try? await asset.load(.metadata) { items += all }
        for identifier in [AVMetadataIdentifier.commonIdentifierArtwork, .iTunesMetadataCoverArt, .id3MetadataAttachedPicture] {
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
                if let data = try? await item.load(.dataValue) { return data }
            }
        }
        return nil
    }

    /// Synchronous wrapper for use on background operation queues.
    static func artworkBlocking(url: URL) -> Data? {
        let box = ResultBox<Data>()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            box.value = await artwork(url: url)
            semaphore.signal()
        }
        semaphore.wait()
        return box.value
    }

    private static func string(_ items: [AVMetadataItem], _ identifiers: [AVMetadataIdentifier]) async -> String? {
        for identifier in identifiers {
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
                if let value = try? await item.load(.stringValue), let text = value.nilIfEmpty { return text }
            }
        }
        return nil
    }

    private static func numberPair(_ items: [AVMetadataItem], _ identifier: AVMetadataIdentifier) async -> (Int?, Int?)? {
        for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
            if let data = try? await item.load(.dataValue), data.count >= 6 {
                let b = [UInt8](data)
                let number = (Int(b[2]) << 8) | Int(b[3])
                let total = (Int(b[4]) << 8) | Int(b[5])
                return (number > 0 ? number : nil, total > 0 ? total : nil)
            }
            if let text = try? await item.load(.stringValue) {
                return MetadataParsing.numberPair(text)
            }
        }
        return nil
    }
}

final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}
