import Foundation

struct ScanFile: Sendable {
    let path: String
    let size: Int64
    let modified: Date
    let created: Date
}

/// Walks library folders and (re)reads metadata for new or changed files.
enum LibraryScanner {
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "aac", "flac", "wav", "aif", "aiff"]

    private static let resourceKeys: [URLResourceKey] = [
        .isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey,
    ]

    static func enumerate(folders: [String]) -> [ScanFile] {
        var seen = Set<String>()
        var files: [ScanFile] = []
        let keySet = Set(resourceKeys)
        for folder in folders {
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: folder, isDirectory: true),
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            while let url = enumerator.nextObject() as? URL {
                guard supportedExtensions.contains(url.pathExtension.lowercased()) else { continue }
                guard let values = try? url.resourceValues(forKeys: keySet), values.isRegularFile == true else { continue }
                let path = url.path
                guard seen.insert(path).inserted else { continue }
                files.append(ScanFile(
                    path: path,
                    size: Int64(values.fileSize ?? 0),
                    modified: values.contentModificationDate ?? .distantPast,
                    created: values.creationDate ?? values.contentModificationDate ?? Date()
                ))
            }
        }
        return files
    }

    static func isReachableDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func scanFile(at url: URL) -> ScanFile? {
        guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)), values.isRegularFile == true else { return nil }
        return ScanFile(
            path: url.path,
            size: Int64(values.fileSize ?? 0),
            modified: values.contentModificationDate ?? .distantPast,
            created: values.creationDate ?? Date()
        )
    }

    /// Scans the folders, reusing cached tracks whose files are unchanged.
    /// `progress` receives (parsed, toParse, partialSnapshot?) — snapshots are sent periodically
    /// during large scans so the UI can fill in progressively.
    static func scan(
        folders: [String],
        cached: [String: Track],
        progress: @escaping @Sendable (Int, Int, [Track]?) -> Void
    ) async -> [Track] {
        // A folder that is missing right now (e.g. on an external drive that isn't connected) keeps
        // its cached tracks instead of emptying out the library until the next scan.
        let available = folders.filter(isReachableDirectory)
        let missing = folders.filter { !available.contains($0) }
        let files = enumerate(folders: available)
        var unchanged: [Track] = cached.values.filter { track in
            missing.contains { LibraryStore.path(track.path, isInside: $0) }
        }
        var toParse: [ScanFile] = []
        for file in files {
            if let track = cached[file.path],
               track.fileSize == file.size,
               abs(track.modificationDate.timeIntervalSince(file.modified)) < 1 {
                unchanged.append(track)
            } else {
                toParse.append(file)
            }
        }

        let total = toParse.count
        progress(0, total, nil)
        guard total > 0 else { return unchanged }

        let snapshotInterval = 250
        let width = max(4, min(ProcessInfo.processInfo.activeProcessorCount, 12))
        let parsed = await withTaskGroup(of: Track?.self, returning: [Track].self) { group in
            var iterator = toParse.makeIterator()
            var collected: [Track] = []
            collected.reserveCapacity(total)
            for _ in 0..<width {
                guard let file = iterator.next() else { break }
                let previous = cached[file.path]
                group.addTask { await parse(file, previous: previous) }
            }
            var done = 0
            for await track in group {
                done += 1
                if let track { collected.append(track) }
                if done % snapshotInterval == 0 {
                    progress(done, total, unchanged + collected)
                } else if done % 10 == 0 || done == total {
                    progress(done, total, nil)
                }
                if let file = iterator.next() {
                    let previous = cached[file.path]
                    group.addTask { await parse(file, previous: previous) }
                }
            }
            return collected
        }
        return unchanged + parsed
    }

    static func parse(_ file: ScanFile, previous: Track?) async -> Track? {
        let url = URL(fileURLWithPath: file.path)
        let meta: RawMetadata
        if url.pathExtension.lowercased() == "mp3" {
            guard let parsed = MP3Reader.read(url: url) else { return nil }
            meta = parsed
        } else {
            meta = await AVMetadataReader.read(url: url)
        }
        return TrackFactory.make(
            path: file.path,
            meta: meta,
            fileSize: file.size,
            modified: file.modified,
            dateAdded: previous?.dateAdded ?? file.created
        )
    }
}
