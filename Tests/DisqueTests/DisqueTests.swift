import Foundation
import Testing
@testable import Disque

private func track(_ path: String, artist: String, album: String = "Album", albumArtist: String? = nil) -> Track {
    var meta = RawMetadata()
    meta.title = (path as NSString).lastPathComponent
    meta.artist = artist
    meta.album = album
    meta.albumArtist = albumArtist
    meta.duration = 180
    return TrackFactory.make(path: path, meta: meta, fileSize: 1, modified: Date(timeIntervalSince1970: 0), dateAdded: Date())
}

// MARK: - Album artist

@Suite struct AlbumArtistTests {
    @Test func guestTracksKeepTheMainArtist() {
        let tracks = [
            track("/m/a/01.mp3", artist: "Band"),
            track("/m/a/02.mp3", artist: "Band feat. Guest"),
            track("/m/a/03.mp3", artist: "Band (ft. Other)"),
        ]
        let index = LibraryIndex.build(from: tracks, revision: 1)
        #expect(index.albums.count == 1)
        #expect(index.albums.first?.artist == "Band")
        #expect(index.albums.first?.isCompilation == false)
    }

    @Test func mixedArtistsStayVariousArtists() {
        let tracks = [
            track("/m/c/01.mp3", artist: "One"),
            track("/m/c/02.mp3", artist: "Two"),
            track("/m/c/03.mp3", artist: "Three"),
        ]
        let index = LibraryIndex.build(from: tracks, revision: 1)
        #expect(index.albums.first?.artist == "Various Artists")
        #expect(index.albums.first?.isCompilation == true)
    }

    @Test func clearMajorityWins() {
        let tracks = [
            track("/m/d/01.mp3", artist: "Main"),
            track("/m/d/02.mp3", artist: "Main"),
            track("/m/d/03.mp3", artist: "Someone Else"),
        ]
        #expect(LibraryIndex.build(from: tracks, revision: 1).albums.first?.artist == "Main")
    }

    @Test func albumArtistTagStillWins() {
        let tracks = [
            track("/m/e/01.mp3", artist: "One", albumArtist: "Label Sampler"),
            track("/m/e/02.mp3", artist: "One", albumArtist: "Label Sampler"),
        ]
        #expect(LibraryIndex.build(from: tracks, revision: 1).albums.first?.artist == "Label Sampler")
    }

    @Test func featuringOnlyMatchesWholeWords() {
        #expect(LibraryIndex.mainArtist("Daft Punk") == "Daft Punk")
        #expect(LibraryIndex.mainArtist("Left Boy") == "Left Boy")
        #expect(LibraryIndex.mainArtist("Band Featuring Guest") == "Band")
        #expect(LibraryIndex.mainArtist("Band [feat. Guest]") == "Band")
    }
}

// MARK: - Unreachable folders

@Suite struct ScannerTests {
    @Test func missingFolderKeepsItsCachedTracks() async throws {
        let present = FileManager.default.temporaryDirectory.appendingPathComponent("disque-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: present, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: present) }
        let missing = "/Volumes/disque-test-not-mounted-\(UUID().uuidString)/Music"

        let onDrive = track(missing + "/Album/01.mp3", artist: "A")
        let deleted = track(present.path + "/gone.mp3", artist: "B")
        let result = await LibraryScanner.scan(
            folders: [present.path, missing],
            cached: [onDrive.path: onDrive, deleted.path: deleted]
        ) { _, _, _ in }

        #expect(result.map(\.path) == [onDrive.path])
    }
}

// MARK: - Player

@MainActor
@Suite(.serialized) struct PlayerTests {
    private func waitUntil(_ timeout: Double = 5, _ condition: () -> Bool) async -> Bool {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    @Test func missingFilesWithRepeatAllStopInsteadOfLooping() async {
        let player = Player()
        while player.repeatMode != .all { player.cycleRepeat() }
        defer { while player.repeatMode != .off { player.cycleRepeat() } }
        let tracks = (1...3).map { track("/nonexistent/disque/\($0).mp3", artist: "X") }

        player.play(tracks, startAt: 0, shuffle: false)
        // Give every file time to fail, then watch: a looping player keeps hopping between tracks.
        try? await Task.sleep(for: .seconds(1))
        var seen = Set<Int?>()
        for _ in 0..<50 {
            seen.insert(player.currentIndex)
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(seen == [0])
        #expect(!player.isPlaying)
        player.stop()
    }

    @Test func restoreFindsTheSavedTrackWhenEarlierFilesAreGone() {
        let tracks = (1...4).map { track("/nonexistent/disque/restore/\($0).mp3", artist: "X") }
        let saver = Player()
        saver.play(tracks, startAt: 2, shuffle: false)
        saver.saveState()
        saver.engineReset()

        // Track 1 disappeared; the current track (3) must still be the restored one.
        let index = LibraryIndex.build(from: [tracks[1], tracks[2], tracks[3]], revision: 1)
        let restorer = Player()
        restorer.restoreState(using: index)
        #expect(restorer.currentTrack?.path == tracks[2].path)
        restorer.engineReset()
    }

    @Test func restoreFallsBackToTheNextTrackWhenTheCurrentOneIsGone() {
        let tracks = (1...4).map { track("/nonexistent/disque/restore2/\($0).mp3", artist: "X") }
        let saver = Player()
        saver.play(tracks, startAt: 1, shuffle: false)
        saver.saveState()
        saver.engineReset()

        let index = LibraryIndex.build(from: [tracks[0], tracks[2], tracks[3]], revision: 1)
        let restorer = Player()
        restorer.restoreState(using: index)
        #expect(restorer.currentTrack?.path == tracks[2].path)
        #expect(restorer.currentTime == 0)
        restorer.engineReset()
    }

    @Test func shuffleCanBeTurnedOffAfterRestore() {
        let tracks = (1...6).map { track("/nonexistent/disque/shuffle/\($0).mp3", artist: "X") }
        let saver = Player()
        saver.play(tracks, startAt: 0, shuffle: false)
        saver.toggleShuffle()
        saver.saveState()
        saver.engineReset()

        let restorer = Player()
        restorer.restoreState(using: LibraryIndex.build(from: tracks, revision: 1))
        #expect(restorer.shuffleEnabled)
        restorer.toggleShuffle()
        #expect(restorer.queue.map(\.track.path) == tracks.map(\.path))
        restorer.engineReset()
    }
}

@MainActor
private extension Player {
    /// Empties the queue without touching the saved state, so a later `Player` can restore it.
    func engineReset() {
        let saved = UserDefaults.standard.data(forKey: "player.state")
        stop()
        UserDefaults.standard.set(saved, forKey: "player.state")
    }
}
