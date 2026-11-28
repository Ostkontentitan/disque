import Foundation

/// Immutable, derived view of the library: albums, artists and genres grouped from the flat track list.
/// Built off the main thread whenever the set of tracks changes.
struct LibraryIndex: Sendable {
    var revision = 0
    var tracks: [Track] = []
    var tracksByID: [String: Track] = [:]
    var albums: [Album] = []
    var albumsByID: [String: Album] = [:]
    var albumIDByTrackID: [String: String] = [:]
    var artists: [Artist] = []
    var artistsByID: [String: Artist] = [:]
    var genres: [Genre] = []
    var genresByID: [String: Genre] = [:]
    var totalDuration: Double = 0

    func album(for track: Track) -> Album? {
        albumIDByTrackID[track.id].flatMap { albumsByID[$0] }
    }

    func artwork(for track: Track) -> ArtworkRequest {
        album(for: track)?.artwork ?? ArtworkRequest(
            key: "track:" + track.id + "|" + Self.artworkVersion(track.hasEmbeddedArtwork ? track : nil),
            embeddedPath: track.hasEmbeddedArtwork ? track.path : nil,
            directory: track.directory,
            seed: track.album
        )
    }

    /// Returns the artist page for a track artist name, if one exists.
    func artist(named name: String) -> Artist? {
        artistsByID[Artist.makeID(name)]
    }

    /// Part of the artwork cache key that changes when the embedded cover changes,
    /// so a rescan never shows a stale (or stale "missing") cover.
    static func artworkVersion(_ track: Track?) -> String {
        guard let track else { return "none" }
        return "\(track.path)#\(track.fileSize)#\(Int(track.modificationDate.timeIntervalSince1970))"
    }

    // MARK: - Building

    static func build(from input: [Track], revision: Int) -> LibraryIndex {
        var index = LibraryIndex()
        index.revision = revision

        // Group tracks into albums.
        var groups: [String: [Track]] = [:]
        for track in input {
            groups[albumKey(for: track), default: []].append(track)
        }

        var albums: [Album] = []
        albums.reserveCapacity(groups.count)
        for (key, members) in groups {
            let sorted = members.sorted(by: trackOrder)
            let first = sorted[0]
            let albumArtistTag = sorted.lazy.compactMap { $0.albumArtist.nonEmpty }.first
            let flaggedCompilation = sorted.contains(where: \.isCompilation)
            let artist: String
            if let albumArtistTag {
                artist = albumArtistTag
            } else if flaggedCompilation {
                artist = "Various Artists"
            } else {
                artist = primaryArtist(of: sorted) ?? "Various Artists"
            }
            let isCompilation = Artist.makeID(artist) == "various artists" || Artist.makeID(artist) == "various"
            let artworkTrack = sorted.first(where: \.hasEmbeddedArtwork)
            let album = Album(
                id: key,
                title: first.album,
                artist: artist,
                artistID: Artist.makeID(artist),
                year: sorted.mostCommon { $0.year },
                genre: sorted.mostCommon { $0.genre },
                tracks: sorted,
                duration: sorted.reduce(0) { $0 + $1.duration },
                dateAdded: sorted.map(\.dateAdded).max() ?? first.dateAdded,
                directory: albumDirectory(first.directory),
                discCount: Set(sorted.map { $0.discNumber ?? 1 }).count,
                isCompilation: isCompilation,
                artwork: ArtworkRequest(
                    key: key + "|" + artworkVersion(artworkTrack),
                    embeddedPath: artworkTrack?.path,
                    directory: first.directory,
                    seed: first.album + artist
                ),
                sortTitle: first.album.sortKey,
                sortArtist: artist.sortKey
            )
            albums.append(album)
        }
        albums.sort { lhs, rhs in
            if lhs.dateAdded != rhs.dateAdded { return lhs.dateAdded > rhs.dateAdded }
            return lhs.sortTitle < rhs.sortTitle
        }

        var albumsByID: [String: Album] = [:]
        var albumIDByTrackID: [String: String] = [:]
        for album in albums {
            albumsByID[album.id] = album
            for track in album.tracks { albumIDByTrackID[track.id] = album.id }
        }

        // Tracks in library order: artist, album, disc, track.
        let orderedTracks = albums
            .sorted { lhs, rhs in
                if lhs.sortArtist != rhs.sortArtist { return lhs.sortArtist < rhs.sortArtist }
                if (lhs.year ?? 0) != (rhs.year ?? 0) { return (lhs.year ?? 0) < (rhs.year ?? 0) }
                return lhs.sortTitle < rhs.sortTitle
            }
            .flatMap(\.tracks)

        // Artists: album artists, plus track artists that appear on other albums/compilations.
        var albumsByArtist: [String: [Album]] = [:]
        var artistNames: [String: String] = [:]
        for album in albums where !album.isCompilation {
            albumsByArtist[album.artistID, default: []].append(album)
            if artistNames[album.artistID] == nil { artistNames[album.artistID] = album.artist }
        }
        var appearsOn: [String: [Album]] = [:]
        var guestTracks: [String: [Track]] = [:]
        for album in albums {
            var seenOnAlbum = Set<String>()
            for track in album.tracks {
                let artistID = Artist.makeID(track.artist)
                guard artistID != album.artistID, !artistID.isEmpty else { continue }
                guard albumsByArtist[artistID] != nil || album.isCompilation else { continue }
                if artistNames[artistID] == nil { artistNames[artistID] = track.artist }
                guestTracks[artistID, default: []].append(track)
                if seenOnAlbum.insert(artistID).inserted {
                    appearsOn[artistID, default: []].append(album)
                }
            }
        }
        let artistIDs = Set(albumsByArtist.keys).union(appearsOn.keys)
        var artists: [Artist] = []
        artists.reserveCapacity(artistIDs.count)
        for id in artistIDs {
            let own = (albumsByArtist[id] ?? []).sorted { ($0.year ?? 0, $0.sortTitle) > ($1.year ?? 0, $1.sortTitle) }
            let guest = (appearsOn[id] ?? []).sorted { ($0.year ?? 0) > ($1.year ?? 0) }
            let tracks = own.flatMap(\.tracks) + (guestTracks[id] ?? [])
            artists.append(Artist(id: id, name: artistNames[id] ?? id, albums: own, appearsOn: guest, tracks: tracks))
        }
        artists.sort { $0.name.sortKey < $1.name.sortKey }

        // Genres.
        var genreAlbums: [String: [Album]] = [:]
        var genreNames: [String: String] = [:]
        for album in albums {
            guard let name = album.genre.nonEmpty else { continue }
            let id = name.searchKey
            genreAlbums[id, default: []].append(album)
            if genreNames[id] == nil { genreNames[id] = name }
        }
        let genres = genreAlbums
            .map { Genre(id: $0.key, name: genreNames[$0.key] ?? $0.key, albums: $0.value) }
            .sorted { $0.name.sortKey < $1.name.sortKey }

        index.tracks = orderedTracks
        index.tracksByID = Dictionary(orderedTracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        index.albums = albums
        index.albumsByID = albumsByID
        index.albumIDByTrackID = albumIDByTrackID
        index.artists = artists
        index.artistsByID = Dictionary(artists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        index.genres = genres
        index.genresByID = Dictionary(genres.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        index.totalDuration = orderedTracks.reduce(0) { $0 + $1.duration }
        return index
    }

    private static let featuringPattern = try! NSRegularExpression(
        pattern: #"\s+[\(\[]?\s*(feat\.?|ft\.?|featuring)\s.*$"#,
        options: [.caseInsensitive]
    )

    /// "Band feat. Guest" → "Band".
    static func mainArtist(_ name: String) -> String {
        let range = NSRange(name.startIndex..., in: name)
        guard let match = featuringPattern.firstMatch(in: name, range: range),
              let matchRange = Range(match.range, in: name) else { return name }
        let base = String(name[..<matchRange.lowerBound]).trimmed
        return base.isEmpty ? name : base
    }

    /// The artist an album without an album-artist tag belongs to: the main artist (ignoring
    /// "feat." guests) of more than half of its tracks. `nil` means it is a various-artists album.
    static func primaryArtist(of tracks: [Track]) -> String? {
        guard !tracks.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        var names: [String: String] = [:]
        for track in tracks {
            let main = mainArtist(track.artist)
            let id = Artist.makeID(main)
            counts[id, default: 0] += 1
            if names[id] == nil { names[id] = main }
            // Prefer the spelling of a track credited to the artist alone.
            if Artist.makeID(track.artist) == id { names[id] = track.artist }
        }
        guard let (id, count) = counts.max(by: { $0.value < $1.value }), count * 2 > tracks.count else { return nil }
        return names[id]
    }

    /// Tracks sharing an album title belong together when they share an album artist,
    /// or (without one) when they live in the same folder.
    static func albumKey(for track: Track) -> String {
        let title = track.album.searchKey.trimmed
        if let albumArtist = track.albumArtist.nonEmpty {
            return "aa:" + albumArtist.searchKey + "|" + title
        }
        return "dir:" + albumDirectory(track.directory) + "|" + title
    }

    private static let discFolderPattern = try! NSRegularExpression(
        pattern: #"^(cd|disc|disk)\s*[-_.]?\s*\d+$"#,
        options: [.caseInsensitive]
    )

    static func isDiscFolder(_ name: String) -> Bool {
        discFolderPattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }

    /// Collapses "CD1"/"Disc 2" style sub-folders into their parent album folder.
    static func albumDirectory(_ directory: String) -> String {
        let name = (directory as NSString).lastPathComponent
        if isDiscFolder(name) { return (directory as NSString).deletingLastPathComponent }
        return directory
    }

    static func trackOrder(_ lhs: Track, _ rhs: Track) -> Bool {
        let lDisc = lhs.discNumber ?? 1, rDisc = rhs.discNumber ?? 1
        if lDisc != rDisc { return lDisc < rDisc }
        let lNum = lhs.trackNumber ?? Int.max, rNum = rhs.trackNumber ?? Int.max
        if lNum != rNum { return lNum < rNum }
        return lhs.fileName.localizedStandardCompare(rhs.fileName) == .orderedAscending
    }
}

// MARK: - Sorting & search

enum AlbumSort: String, CaseIterable, Identifiable {
    case recentlyAdded, title, artist, newest, oldest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        case .title: "Album Title"
        case .artist: "Artist"
        case .newest: "Release Date (Newest)"
        case .oldest: "Release Date (Oldest)"
        }
    }

    func apply(_ albums: [Album]) -> [Album] {
        switch self {
        case .recentlyAdded:
            return albums.sorted { ($0.dateAdded, $1.sortTitle) > ($1.dateAdded, $0.sortTitle) }
        case .title:
            return albums.sorted { ($0.sortTitle, $0.sortArtist) < ($1.sortTitle, $1.sortArtist) }
        case .artist:
            return albums.sorted { lhs, rhs in
                if lhs.sortArtist != rhs.sortArtist { return lhs.sortArtist < rhs.sortArtist }
                if (lhs.year ?? 0) != (rhs.year ?? 0) { return (lhs.year ?? 0) < (rhs.year ?? 0) }
                return lhs.sortTitle < rhs.sortTitle
            }
        case .newest:
            return albums.sorted { ($0.year ?? 0, $1.sortTitle) > ($1.year ?? 0, $0.sortTitle) }
        case .oldest:
            return albums.sorted { ($0.year ?? Int.max, $0.sortTitle) < ($1.year ?? Int.max, $1.sortTitle) }
        }
    }
}

enum TrackSortKey: String, CaseIterable, Identifiable {
    case title, artist, album, duration, recentlyAdded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .album: "Album"
        case .duration: "Duration"
        case .recentlyAdded: "Recently Added"
        }
    }

    /// `tracks` is expected in library order (artist/album/disc/track), which is used as the tie breaker.
    static func sort(_ tracks: [Track], by key: TrackSortKey, ascending: Bool) -> [Track] {
        if key == .artist {
            return ascending ? tracks : sortStable(tracks) { $0.artist.sortKey > $1.artist.sortKey }
        }
        let keyed: [(String, Double, Int, Track)] = tracks.enumerated().map { offset, track in
            switch key {
            case .title: (track.title.sortKey, 0, offset, track)
            case .album: (track.album.sortKey, 0, offset, track)
            case .duration: ("", track.duration, offset, track)
            case .recentlyAdded: ("", -track.dateAdded.timeIntervalSinceReferenceDate, offset, track)
            case .artist: ("", 0, offset, track)
            }
        }
        let sorted = keyed.sorted { lhs, rhs in
            if lhs.0 != rhs.0 { return ascending ? lhs.0 < rhs.0 : lhs.0 > rhs.0 }
            if lhs.1 != rhs.1 { return ascending ? lhs.1 < rhs.1 : lhs.1 > rhs.1 }
            return lhs.2 < rhs.2
        }
        return sorted.map(\.3)
    }

    private static func sortStable(_ tracks: [Track], by areInIncreasingOrder: (Track, Track) -> Bool) -> [Track] {
        tracks.enumerated()
            .sorted { lhs, rhs in
                if areInIncreasingOrder(lhs.element, rhs.element) { return true }
                if areInIncreasingOrder(rhs.element, lhs.element) { return false }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

struct SearchResults: Sendable {
    var artists: [Artist] = []
    var albums: [Album] = []
    var tracks: [Track] = []

    var isEmpty: Bool { artists.isEmpty && albums.isEmpty && tracks.isEmpty }

    static func compute(query: String, in index: LibraryIndex) -> SearchResults {
        let tokens = query.searchKey.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return SearchResults() }
        func matches(_ haystack: String) -> Bool {
            tokens.allSatisfy { haystack.contains($0) }
        }
        var results = SearchResults()
        results.artists = index.artists.filter { matches($0.name.searchKey) }
        results.albums = index.albums
            .filter { matches(($0.title + " " + $0.artist + " " + ($0.genre ?? "")).searchKey) }
            .sorted { $0.sortTitle < $1.sortTitle }
        results.tracks = index.tracks.filter { matches(($0.title + " " + $0.artist + " " + $0.album).searchKey) }
        // Prefer exact-ish title matches first.
        let lowered = query.searchKey.trimmed
        results.artists.sort { ($0.name.searchKey.hasPrefix(lowered) ? 0 : 1, $0.name.sortKey) < ($1.name.searchKey.hasPrefix(lowered) ? 0 : 1, $1.name.sortKey) }
        results.tracks.sort { ($0.title.searchKey.hasPrefix(lowered) ? 0 : 1) < ($1.title.searchKey.hasPrefix(lowered) ? 0 : 1) }
        return results
    }
}
