import AppKit
import Foundation
import Observation

/// Owns the library: folders, scanned tracks, derived index, favourites, playlists and history.
@MainActor
@Observable
final class LibraryStore {
    private(set) var index = LibraryIndex()
    private(set) var folders: [String]
    private(set) var hasLoaded = false
    private(set) var isScanning = false
    private(set) var scanCompleted = 0
    private(set) var scanTotal = 0
    private(set) var favoriteTracks: [String: Date] = [:]
    private(set) var favoriteAlbums: [String: Date] = [:]
    private(set) var favoriteArtists: [String: Date] = [:]
    private(set) var playlists: [Playlist] = []
    private(set) var history: [HistoryEntry] = []

    @ObservationIgnored private var tracksByPath: [String: Track] = [:]
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var scanGeneration = 0
    @ObservationIgnored private var acceptingPartialResults = false
    @ObservationIgnored private var rescanPending = false
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var saveStateTask: Task<Void, Never>?
    @ObservationIgnored private var mountObserver: NSObjectProtocol?

    private static let foldersKey = "libraryFolders"

    init() {
        folders = UserDefaults.standard.stringArray(forKey: Self.foldersKey) ?? []
        if let state = Persistence.loadState() {
            favoriteTracks = state.favoriteTracks
            favoriteAlbums = state.favoriteAlbums
            favoriteArtists = state.favoriteArtists
            playlists = state.playlists
            history = state.history
        }
    }

    // MARK: - Loading & scanning

    /// Loads the cached library, then kicks off an incremental rescan.
    func start() async {
        guard !hasLoaded else { return }
        let cached = await Task.detached(priority: .userInitiated) { Persistence.loadTracks() }.value
        let roots = folders
        let relevant = cached.filter { track in roots.contains { Self.path(track.path, isInside: $0) } }
        await rebuildIndex(with: relevant)
        hasLoaded = true
        restartWatcher()
        // Folders on external drives come back when the drive is connected again.
        mountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restartWatcher()
                self?.rescan()
            }
        }
        rescan()
    }

    func rescan() {
        guard hasLoaded else { return }
        if isScanning {
            rescanPending = true
            return
        }
        isScanning = true
        scanCompleted = 0
        scanTotal = 0
        scanGeneration += 1
        acceptingPartialResults = true
        let generation = scanGeneration
        let roots = folders
        let cached = tracksByPath

        Task {
            let tracks = await LibraryScanner.scan(folders: roots, cached: cached) { @Sendable done, total, partial in
                Task { @MainActor in
                    guard generation == self.scanGeneration, self.acceptingPartialResults else { return }
                    self.scanCompleted = done
                    self.scanTotal = total
                    if let partial { await self.rebuildIndex(with: partial) }
                }
            }
            acceptingPartialResults = false
            // Folders may have been removed while scanning.
            let currentRoots = folders
            let kept = tracks.filter { track in currentRoots.contains { Self.path(track.path, isInside: $0) } }
            await rebuildIndex(with: kept)
            Task.detached(priority: .utility) { Persistence.saveTracks(kept) }
            isScanning = false
            if rescanPending {
                rescanPending = false
                rescan()
            }
        }
    }

    /// Forgets all cached metadata and reads every file again.
    func rebuildFromScratch() {
        Persistence.deleteTrackCache()
        tracksByPath = [:]
        rescan()
    }

    private func rebuildIndex(with tracks: [Track]) async {
        tracksByPath = Dictionary(tracks.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        revision += 1
        let current = revision
        let built = await Task.detached(priority: .userInitiated) { LibraryIndex.build(from: tracks, revision: current) }.value
        if current == revision { index = built }
    }

    private func restartWatcher() {
        watcher = FolderWatcher(paths: folders) { [weak self] in
            self?.rescan()
        }
    }

    // MARK: - Folders

    func presentAddFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add to Library"
        panel.message = "Choose folders that contain your music."
        panel.directoryURL = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            MainActor.assumeIsolated { self?.addFolders(urls) }
        }
    }

    func addFolders(_ urls: [URL]) {
        var changed = false
        for url in urls {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            if folders.contains(where: { Self.path(path, isInside: $0) || $0 == path }) { continue }
            folders.removeAll { Self.path($0, isInside: path) }
            folders.append(path)
            changed = true
        }
        guard changed else { return }
        folders.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        UserDefaults.standard.set(folders, forKey: Self.foldersKey)
        restartWatcher()
        rescan()
    }

    func removeFolder(_ path: String) {
        folders.removeAll { $0 == path }
        UserDefaults.standard.set(folders, forKey: Self.foldersKey)
        restartWatcher()
        let roots = folders
        let remaining = tracksByPath.values.filter { track in roots.contains { Self.path(track.path, isInside: $0) } }
        Task {
            await rebuildIndex(with: Array(remaining))
            let snapshot = Array(remaining)
            Task.detached(priority: .utility) { Persistence.saveTracks(snapshot) }
        }
    }

    nonisolated static func path(_ path: String, isInside folder: String) -> Bool {
        path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }

    // MARK: - Favourites

    func isFavorite(_ track: Track) -> Bool { favoriteTracks[track.id] != nil }
    func isFavorite(_ album: Album) -> Bool { favoriteAlbums[album.id] != nil }
    func isFavorite(_ artist: Artist) -> Bool { favoriteArtists[artist.id] != nil }

    func toggleFavorite(_ track: Track) {
        favoriteTracks[track.id] = favoriteTracks[track.id] == nil ? Date() : nil
        scheduleStateSave()
    }

    func toggleFavorite(_ album: Album) {
        favoriteAlbums[album.id] = favoriteAlbums[album.id] == nil ? Date() : nil
        scheduleStateSave()
    }

    func toggleFavorite(_ artist: Artist) {
        favoriteArtists[artist.id] = favoriteArtists[artist.id] == nil ? Date() : nil
        scheduleStateSave()
    }

    var favoriteTrackList: [Track] {
        favoriteTracks.sorted { $0.value > $1.value }.compactMap { index.tracksByID[$0.key] }
    }

    var favoriteAlbumList: [Album] {
        favoriteAlbums.sorted { $0.value > $1.value }.compactMap { index.albumsByID[$0.key] }
    }

    var favoriteArtistList: [Artist] {
        favoriteArtists.sorted { $0.value > $1.value }.compactMap { index.artistsByID[$0.key] }
    }

    // MARK: - Playlists

    func playlist(_ id: UUID) -> Playlist? { playlists.first { $0.id == id } }

    func tracks(in playlist: Playlist) -> [Track] {
        playlist.trackPaths.compactMap { index.tracksByID[$0] }
    }

    @discardableResult
    func createPlaylist(name: String, tracks: [Track] = []) -> Playlist {
        let title = name.nilIfEmpty ?? "New Playlist"
        let playlist = Playlist(id: UUID(), name: title, trackPaths: tracks.map(\.path), created: Date(), modified: Date())
        playlists.append(playlist)
        scheduleStateSave()
        return playlist
    }

    func renamePlaylist(_ id: UUID, to name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }), let title = name.nilIfEmpty else { return }
        playlists[i].name = title
        playlists[i].modified = Date()
        scheduleStateSave()
    }

    func deletePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        scheduleStateSave()
    }

    func addTracks(_ tracks: [Track], toPlaylist id: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].trackPaths += tracks.map(\.path)
        playlists[i].modified = Date()
        scheduleStateSave()
    }

    func removeTrack(at offset: Int, fromPlaylist id: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == id }), playlists[i].trackPaths.indices.contains(offset) else { return }
        playlists[i].trackPaths.remove(at: offset)
        playlists[i].modified = Date()
        scheduleStateSave()
    }

    func moveTracks(inPlaylist id: UUID, from source: IndexSet, to destination: Int) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].trackPaths.move(fromOffsets: source, toOffset: destination)
        playlists[i].modified = Date()
        scheduleStateSave()
    }

    // MARK: - History

    func recordPlay(_ track: Track) {
        history.removeAll { $0.path == track.path && Date().timeIntervalSince($0.date) < 5 }
        history.insert(HistoryEntry(id: UUID(), path: track.path, date: Date()), at: 0)
        if history.count > 500 { history.removeLast(history.count - 500) }
        scheduleStateSave()
    }

    func clearHistory() {
        history.removeAll()
        scheduleStateSave()
    }

    // MARK: - Persistence

    private func scheduleStateSave() {
        saveStateTask?.cancel()
        saveStateTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            saveStateNow()
        }
    }

    func saveStateNow(synchronously: Bool = false) {
        saveStateTask?.cancel()
        let state = SavedLibraryState(
            favoriteTracks: favoriteTracks,
            favoriteAlbums: favoriteAlbums,
            favoriteArtists: favoriteArtists,
            playlists: playlists,
            history: history
        )
        if synchronously {
            Persistence.saveState(state)
        } else {
            Task.detached(priority: .utility) { Persistence.saveState(state) }
        }
    }
}
