import AppKit
import Foundation
import ImageIO

/// Loads, downsamples and caches album artwork from embedded tags or cover files next to the music.
final class ArtworkLoader: @unchecked Sendable {
    static let shared = ArtworkLoader()

    private final class Entry {
        let image: NSImage?
        init(_ image: NSImage?) { self.image = image }
    }

    private final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }

    private let cache = NSCache<NSString, Entry>()
    private let queue: OperationQueue
    private let folderLock = NSLock()
    private var folderCovers: [String: String] = [:]
    private var foldersWithoutCover: Set<String> = []

    private static let coverNames = ["cover", "folder", "front", "album", "albumart", "artwork"]
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "tif", "tiff", "bmp", "gif"]

    private init() {
        cache.countLimit = 800
        queue = OperationQueue()
        queue.name = "Disque.Artwork"
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .userInitiated
    }

    private func key(_ request: ArtworkRequest, _ pixelSize: Int) -> NSString {
        "\(request.key)@\(pixelSize)" as NSString
    }

    /// Returns `nil` when not cached yet (or cached as missing).
    func cachedImage(for request: ArtworkRequest, pixelSize: Int) -> NSImage? {
        cache.object(forKey: key(request, pixelSize))?.image
    }

    func image(for request: ArtworkRequest, pixelSize: Int) async -> NSImage? {
        let keyString = "\(request.key)@\(pixelSize)"
        if let hit = cache.object(forKey: keyString as NSString) { return hit.image }
        let flag = CancelFlag()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
                queue.addOperation { [self] in
                    let cacheKey = keyString as NSString
                    if flag.isCancelled {
                        continuation.resume(returning: nil)
                        return
                    }
                    if let hit = cache.object(forKey: cacheKey) {
                        continuation.resume(returning: hit.image)
                        return
                    }
                    let image = decode(request, pixelSize: pixelSize)
                    cache.setObject(Entry(image), forKey: cacheKey)
                    continuation.resume(returning: image)
                }
            }
        } onCancel: {
            flag.cancel()
        }
    }

    private func decode(_ request: ArtworkRequest, pixelSize: Int) -> NSImage? {
        if let path = request.embeddedPath, let data = Self.embeddedArtwork(path: path),
           let image = Self.thumbnail(source: CGImageSourceCreateWithData(data as CFData, nil), maxPixel: pixelSize) {
            return image
        }
        if let cover = folderCover(in: request.directory),
           let image = Self.thumbnail(source: CGImageSourceCreateWithURL(URL(fileURLWithPath: cover) as CFURL, nil), maxPixel: pixelSize) {
            return image
        }
        return nil
    }

    static func embeddedArtwork(path: String) -> Data? {
        let url = URL(fileURLWithPath: path)
        if url.pathExtension.lowercased() == "mp3" { return MP3Reader.artwork(url: url) }
        return AVMetadataReader.artworkBlocking(url: url)
    }

    private static func thumbnail(source: CGImageSource?, maxPixel: Int) -> NSImage? {
        guard let source else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    /// Finds a cover image file in the album folder (or its parent for CD1/CD2 style folders).
    func folderCover(in directory: String) -> String? {
        folderLock.lock()
        if let cached = folderCovers[directory] {
            folderLock.unlock()
            return cached
        }
        if foldersWithoutCover.contains(directory) {
            folderLock.unlock()
            return nil
        }
        folderLock.unlock()

        var found = Self.findCover(in: directory)
        if found == nil, LibraryIndex.isDiscFolder((directory as NSString).lastPathComponent) {
            found = Self.findCover(in: (directory as NSString).deletingLastPathComponent)
        }

        folderLock.lock()
        if let found { folderCovers[directory] = found } else { foldersWithoutCover.insert(directory) }
        folderLock.unlock()
        return found
    }

    private static func findCover(in directory: String) -> String? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return nil }
        let images = names.filter { imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) && !$0.hasPrefix(".") }
        guard !images.isEmpty else { return nil }
        for preferred in coverNames {
            if let match = images.first(where: { ($0 as NSString).deletingPathExtension.lowercased().hasPrefix(preferred) }) {
                return (directory as NSString).appendingPathComponent(match)
            }
        }
        let fallback = images.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.first!
        return (directory as NSString).appendingPathComponent(fallback)
    }

    func clearFolderCache() {
        folderLock.withLock {
            folderCovers.removeAll()
            foldersWithoutCover.removeAll()
        }
    }
}
