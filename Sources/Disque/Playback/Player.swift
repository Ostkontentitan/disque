import AppKit
import AVFoundation
import MediaPlayer
import Observation

enum RepeatMode: Int, Codable {
    case off, all, one
}

struct QueueEntry: Identifiable, Equatable {
    let id: UUID
    let track: Track

    init(_ track: Track) {
        id = UUID()
        self.track = track
    }
}

/// An AVPlayerItem that remembers which queue entry it belongs to.
final class QueuedPlayerItem: AVPlayerItem {
    let entryID: UUID

    init(url: URL, entryID: UUID) {
        self.entryID = entryID
        super.init(asset: AVURLAsset(url: url), automaticallyLoadedAssetKeys: ["duration"])
    }
}

/// Playback engine: an ordered queue on top of AVQueuePlayer (next item preloaded for near-gapless
/// transitions), shuffle/repeat, Now Playing + media keys, and state restoration.
@MainActor
@Observable
final class Player {
    private(set) var queue: [QueueEntry] = []
    private(set) var currentIndex: Int?
    private(set) var currentTrackID: String?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var shuffleEnabled = false
    private(set) var repeatMode: RepeatMode = .off
    private(set) var sourceName: String?

    var volume: Double = 0.8 {
        didSet {
            applyVolume()
            UserDefaults.standard.set(volume, forKey: Keys.volume)
        }
    }

    var isMuted = false {
        didSet { applyVolume() }
    }

    @ObservationIgnored weak var library: LibraryStore?
    @ObservationIgnored private let engine = AVQueuePlayer()
    @ObservationIgnored private var unshuffledQueue: [QueueEntry]?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var activeItem: AVPlayerItem?
    @ObservationIgnored private var artworkImage: NSImage?
    @ObservationIgnored private var pendingSeek: Double?
    @ObservationIgnored private var isRestoring = false
    /// Track to add to the history once its item has actually loaded (missing files never count as played).
    @ObservationIgnored private var pendingPlayRecord: Track?
    /// Items that failed in a row; once every queue entry has failed, playback stops instead of looping.
    @ObservationIgnored private var consecutiveFailures = 0

    private enum Keys {
        static let volume = "player.volume"
        static let repeatMode = "player.repeat"
        static let state = "player.state"
    }

    private struct SavedState: Codable {
        var paths: [String]
        var index: Int?
        var time: Double
        var shuffle: Bool
        var source: String?
        /// Queue order before shuffling, so turning shuffle off still works after a relaunch.
        var unshuffledPaths: [String]?
    }

    var currentEntry: QueueEntry? {
        guard let currentIndex, queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    var currentTrack: Track? { currentEntry?.track }

    var upcoming: [QueueEntry] {
        guard let currentIndex else { return queue }
        guard currentIndex + 1 < queue.count else { return [] }
        return Array(queue[(currentIndex + 1)...])
    }

    var hasQueue: Bool { !queue.isEmpty }

    init() {
        if let saved = UserDefaults.standard.object(forKey: Keys.volume) as? Double {
            volume = min(max(saved, 0), 1)
        }
        repeatMode = RepeatMode(rawValue: UserDefaults.standard.integer(forKey: Keys.repeatMode)) ?? .off
        engine.actionAtItemEnd = .advance
        applyVolume()

        timeObserver = engine.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 4),
            queue: .main
        ) { @Sendable [weak self] time in
            MainActor.assumeIsolated { self?.handleTick(time) }
        }
        observations.append(engine.observe(\.timeControlStatus, options: [.new]) { @Sendable [weak self] _, _ in
            Task { @MainActor in self?.handleStatusChange() }
        })
        observations.append(engine.observe(\.currentItem, options: [.new]) { @Sendable [weak self] _, _ in
            Task { @MainActor in self?.handleCurrentItemChange() }
        })
        configureRemoteCommands()
    }

    // MARK: - Starting playback

    /// Replaces the queue with `tracks` and starts playing.
    /// - Parameter shuffle: `true` shuffles everything (random first track); `nil` keeps the current shuffle mode.
    func play(_ tracks: [Track], startAt index: Int = 0, shuffle: Bool? = nil, source: String? = nil) {
        guard !tracks.isEmpty else { return }
        let entries = tracks.map(QueueEntry.init)
        let start = min(max(index, 0), entries.count - 1)
        consecutiveFailures = 0
        sourceName = source
        if let shuffle { shuffleEnabled = shuffle }

        if shuffleEnabled {
            unshuffledQueue = entries
            var rest = entries
            let first: QueueEntry
            if shuffle == true {
                rest.shuffle()
                first = rest.removeFirst()
            } else {
                first = rest.remove(at: start)
                rest.shuffle()
            }
            queue = [first] + rest
            startPlayback(at: 0)
        } else {
            unshuffledQueue = nil
            queue = entries
            startPlayback(at: start)
        }
    }

    func togglePlayPause() {
        if engine.currentItem == nil {
            if let index = currentIndex ?? (queue.isEmpty ? nil : 0) { startPlayback(at: index) }
            return
        }
        if engine.timeControlStatus == .paused { engine.play() } else { engine.pause() }
    }

    func resume() {
        if engine.currentItem == nil { togglePlayPause() } else { engine.play() }
    }

    func pause() {
        engine.pause()
    }

    func next() {
        guard let currentIndex else { return }
        if let next = nextIndex(after: currentIndex, automatic: false) {
            startPlayback(at: next)
        } else {
            finishQueue()
        }
    }

    func previous() {
        guard let currentIndex else { return }
        if currentTime > 3 || (currentIndex == 0 && repeatMode != .all) {
            seek(to: 0)
            return
        }
        let previous = currentIndex > 0 ? currentIndex - 1 : queue.count - 1
        startPlayback(at: previous)
    }

    func seek(to seconds: Double) {
        guard engine.currentItem != nil else { return }
        let target = max(0, min(seconds, duration > 0 ? duration : seconds))
        currentTime = target
        // Sample-exact seeks force AVFoundation to scan MP3 streams from the start (slow on long files);
        // a small tolerance keeps scrubbing instant.
        let tolerance = CMTime(seconds: 0.25, preferredTimescale: 600)
        engine.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        ) { @Sendable [weak self] _ in
            Task { @MainActor in self?.updateNowPlaying() }
        }
    }

    func stop() {
        engine.removeAllItems()
        activeItem = nil
        queue = []
        unshuffledQueue = nil
        currentIndex = nil
        currentTrackID = nil
        currentTime = 0
        duration = 0
        sourceName = nil
        isPlaying = false
        updateNowPlaying()
        saveState()
    }

    // MARK: - Queue editing

    func playNext(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        guard let currentIndex, !queue.isEmpty else {
            play(tracks)
            return
        }
        let entries = tracks.map(QueueEntry.init)
        let anchor = queue[currentIndex].id
        queue.insert(contentsOf: entries, at: currentIndex + 1)
        if var original = unshuffledQueue, let i = original.firstIndex(where: { $0.id == anchor }) {
            original.insert(contentsOf: entries, at: i + 1)
            unshuffledQueue = original
        }
        enqueueNext()
        saveState()
    }

    func addToQueue(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        guard currentIndex != nil, !queue.isEmpty else {
            play(tracks)
            return
        }
        let entries = tracks.map(QueueEntry.init)
        queue.append(contentsOf: entries)
        unshuffledQueue?.append(contentsOf: entries)
        enqueueNext()
        saveState()
    }

    func jump(to entryID: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == entryID }) else { return }
        consecutiveFailures = 0
        startPlayback(at: index)
    }

    func remove(_ entryID: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == entryID }) else { return }
        unshuffledQueue?.removeAll { $0.id == entryID }
        if index == currentIndex {
            let wasPlaying = isPlaying
            queue.remove(at: index)
            if queue.isEmpty {
                stop()
            } else {
                startPlayback(at: min(index, queue.count - 1), autoplay: wasPlaying)
            }
            return
        }
        queue.remove(at: index)
        if let currentIndex, index < currentIndex { self.currentIndex = currentIndex - 1 }
        enqueueNext()
        saveState()
    }

    /// Moves items within the "up next" section (offsets are relative to `upcoming`).
    func moveUpcoming(from source: IndexSet, to destination: Int) {
        guard let currentIndex else {
            queue.move(fromOffsets: source, toOffset: destination)
            return
        }
        var rest = upcoming
        rest.move(fromOffsets: source, toOffset: destination)
        queue = Array(queue[...currentIndex]) + rest
        enqueueNext()
        saveState()
    }

    func clearUpcoming() {
        guard let currentIndex else {
            stop()
            return
        }
        let removed = Set(upcoming.map(\.id))
        queue = Array(queue[...currentIndex])
        unshuffledQueue?.removeAll { removed.contains($0.id) }
        enqueueNext()
        saveState()
    }

    // MARK: - Modes

    func toggleShuffle() {
        if shuffleEnabled {
            shuffleEnabled = false
            if let original = unshuffledQueue {
                let currentID = currentEntry?.id
                queue = original
                currentIndex = currentID.flatMap { id in queue.firstIndex { $0.id == id } } ?? (queue.isEmpty ? nil : 0)
            }
            unshuffledQueue = nil
        } else {
            shuffleEnabled = true
            unshuffledQueue = queue
            if let currentIndex {
                let current = queue[currentIndex]
                var rest = queue
                rest.remove(at: currentIndex)
                rest.shuffle()
                queue = [current] + rest
                self.currentIndex = 0
            } else {
                queue.shuffle()
            }
        }
        enqueueNext()
        saveState()
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        UserDefaults.standard.set(repeatMode.rawValue, forKey: Keys.repeatMode)
        enqueueNext()
    }

    func toggleMute() {
        isMuted.toggle()
    }

    // MARK: - Engine plumbing

    private func makeItem(_ entry: QueueEntry) -> QueuedPlayerItem {
        QueuedPlayerItem(url: entry.track.url, entryID: entry.id)
    }

    private func startPlayback(at index: Int, autoplay: Bool = true) {
        guard queue.indices.contains(index) else { return }
        engine.removeAllItems()
        activeItem = nil
        currentIndex = index
        currentTrackID = queue[index].track.id
        duration = queue[index].track.duration
        currentTime = 0
        let item = makeItem(queue[index])
        engine.insert(item, after: nil)
        if autoplay { engine.play() } else { engine.pause() }
        handleCurrentItemChange()
    }

    private func nextIndex(after index: Int, automatic: Bool) -> Int? {
        guard !queue.isEmpty else { return nil }
        if automatic && repeatMode == .one { return index }
        if index + 1 < queue.count { return index + 1 }
        if repeatMode != .off { return 0 }
        return nil
    }

    /// Keeps exactly one preloaded item after the current one so transitions are seamless.
    private func enqueueNext() {
        guard let current = engine.currentItem else { return }
        for item in engine.items() where item !== current {
            engine.remove(item)
        }
        guard let currentIndex, let next = nextIndex(after: currentIndex, automatic: true) else { return }
        let item = makeItem(queue[next])
        if engine.canInsert(item, after: current) {
            engine.insert(item, after: current)
        }
    }

    private func handleCurrentItemChange() {
        let item = engine.currentItem
        guard item !== activeItem else { return }
        activeItem = item
        guard let queued = item as? QueuedPlayerItem else {
            if item == nil, currentIndex != nil { finishQueue() }
            return
        }
        guard let index = queue.firstIndex(where: { $0.id == queued.entryID }) else { return }
        currentIndex = index
        trackDidStart(queued)
    }

    private func trackDidStart(_ item: QueuedPlayerItem) {
        guard let track = currentTrack else { return }
        currentTrackID = track.id
        duration = track.duration
        if !isRestoring {
            currentTime = 0
        }
        pendingPlayRecord = isRestoring ? nil : track
        observeStatus(of: item)
        enqueueNext()
        loadArtwork(for: track)
        updateNowPlaying()
        saveState()
    }

    private func observeStatus(of item: QueuedPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { @Sendable [weak self] item, _ in
            Task { @MainActor in
                guard let self, item === self.activeItem else { return }
                switch item.status {
                case .readyToPlay:
                    self.consecutiveFailures = 0
                    if let track = self.pendingPlayRecord {
                        self.pendingPlayRecord = nil
                        self.library?.recordPlay(track)
                    }
                    let seconds = item.duration.seconds
                    if seconds.isFinite, seconds > 0 { self.duration = seconds }
                    if let seek = self.pendingSeek {
                        self.pendingSeek = nil
                        self.seek(to: seek)
                    }
                    self.updateNowPlaying()
                case .failed:
                    self.handleFailedItem()
                default:
                    break
                }
            }
        }
    }

    private func handleFailedItem() {
        guard let currentIndex else { return }
        pendingPlayRecord = nil
        consecutiveFailures += 1
        // With repeat on, `nextIndex` wraps around; stop once every entry has failed.
        if consecutiveFailures >= queue.count {
            consecutiveFailures = 0
            finishQueue()
            return
        }
        if let next = nextIndex(after: currentIndex, automatic: false), next != currentIndex {
            startPlayback(at: next)
        } else {
            finishQueue()
        }
    }

    /// End of queue: rewind to the first track, paused, like most players.
    private func finishQueue() {
        // AVQueuePlayer keeps its rate at 1 after running out of items; reset it so the
        // status (and the next play) behave.
        engine.pause()
        engine.removeAllItems()
        activeItem = nil
        isPlaying = false
        currentTime = 0
        if queue.isEmpty {
            currentIndex = nil
            currentTrackID = nil
            duration = 0
        } else {
            currentIndex = 0
            currentTrackID = queue[0].track.id
            duration = queue[0].track.duration
            loadArtwork(for: queue[0].track)
        }
        updateNowPlaying()
        saveState()
    }

    private func handleTick(_ time: CMTime) {
        guard activeItem != nil else { return }
        let seconds = time.seconds
        if seconds.isFinite, seconds >= 0 { currentTime = seconds }
    }

    private func handleStatusChange() {
        let playing = engine.currentItem != nil && engine.timeControlStatus != .paused
        guard playing != isPlaying else { return }
        isPlaying = playing
        updateNowPlaying()
        if !playing { saveState() }
    }

    private func applyVolume() {
        // Perceptual curve: linear slider positions feel more natural squared.
        engine.volume = isMuted ? 0 : Float(volume * volume)
    }

    // MARK: - Now Playing & media keys

    private func loadArtwork(for track: Track) {
        artworkImage = nil
        guard let request = library?.index.artwork(for: track) else { return }
        let trackID = track.id
        Task { [weak self] in
            let image = await ArtworkLoader.shared.image(for: request, pixelSize: 600)
            guard let self, self.currentTrackID == trackID else { return }
            self.artworkImage = image
            self.updateNowPlaying()
        }
    }

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard let track = currentTrack else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let image = artworkImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { @Sendable [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.seek(to: position) }
            return .success
        }
    }

    // MARK: - State restoration

    func saveState() {
        let state = SavedState(
            paths: queue.map(\.track.path),
            index: currentIndex,
            time: currentTime,
            shuffle: shuffleEnabled,
            source: sourceName,
            unshuffledPaths: unshuffledQueue?.map(\.track.path)
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Keys.state)
        }
    }

    /// Restores the last queue (paused, at the last position) once the library is loaded.
    func restoreState(from library: LibraryStore) {
        restoreState(using: library.index)
    }

    func restoreState(using index: LibraryIndex) {
        guard queue.isEmpty,
              let data = UserDefaults.standard.data(forKey: Keys.state),
              let state = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        // Files may have disappeared since the state was saved; keep their saved positions so the
        // current track is found again instead of shifting to a neighbour.
        let available: [(offset: Int, entry: QueueEntry)] = state.paths.enumerated().compactMap { offset, path in
            index.tracksByID[path].map { (offset, QueueEntry($0)) }
        }
        guard !available.isEmpty else { return }
        queue = available.map(\.entry)
        shuffleEnabled = state.shuffle
        sourceName = state.source
        unshuffledQueue = shuffleEnabled ? Self.restoreOrder(of: queue, paths: state.unshuffledPaths) : nil

        let savedIndex = state.index ?? 0
        let start = available.firstIndex { $0.offset >= savedIndex } ?? 0
        // Only resume mid-track if the saved current track is still there.
        let time = available[start].offset == savedIndex ? state.time : 0
        pendingSeek = time > 1 ? time : nil
        isRestoring = true
        startPlayback(at: start, autoplay: false)
        isRestoring = false
        currentTime = time
    }

    /// Rebuilds the pre-shuffle order from saved paths, reusing the restored queue entries.
    private static func restoreOrder(of entries: [QueueEntry], paths: [String]?) -> [QueueEntry] {
        guard let paths else { return entries }
        var remaining = entries
        var ordered: [QueueEntry] = []
        for path in paths {
            if let i = remaining.firstIndex(where: { $0.track.path == path }) {
                ordered.append(remaining.remove(at: i))
            }
        }
        return ordered + remaining
    }
}
