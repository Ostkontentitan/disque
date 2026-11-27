import Foundation

struct SavedLibraryState: Codable {
    var favoriteTracks: [String: Date] = [:]
    var favoriteAlbums: [String: Date] = [:]
    var favoriteArtists: [String: Date] = [:]
    var playlists: [Playlist] = []
    var history: [HistoryEntry] = []
}

/// Stores the scanned track cache and user state in ~/Library/Application Support/Disque.
enum Persistence {
    private struct TrackCache: Codable {
        var version: Int
        var tracks: [Track]
    }

    private static let cacheVersion = 1

    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Disque", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private static var tracksURL: URL { directory.appendingPathComponent("library.json") }
    private static var stateURL: URL { directory.appendingPathComponent("state.json") }

    static func loadTracks() -> [Track] {
        guard let data = try? Data(contentsOf: tracksURL),
              let cache = try? JSONDecoder().decode(TrackCache.self, from: data),
              cache.version == cacheVersion else { return [] }
        return cache.tracks
    }

    static func saveTracks(_ tracks: [Track]) {
        guard let data = try? JSONEncoder().encode(TrackCache(version: cacheVersion, tracks: tracks)) else { return }
        try? data.write(to: tracksURL, options: .atomic)
    }

    static func deleteTrackCache() {
        try? FileManager.default.removeItem(at: tracksURL)
    }

    static func loadState() -> SavedLibraryState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(SavedLibraryState.self, from: data)
    }

    static func saveState(_ state: SavedLibraryState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }
}
