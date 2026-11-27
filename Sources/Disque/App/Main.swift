import Foundation

@main
enum Entry {
    static func main() {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--dump-metadata") {
            MetadataDump.run(paths: Array(arguments[(flag + 1)...]))
            return
        }
        #if DEBUG
        if let flag = arguments.firstIndex(of: "--selftest-playback") {
            let paths = Array(arguments[(flag + 1)...])
            MainActor.assumeIsolated { PlaybackSelfTest.run(paths: paths) }
            dispatchMain()
        }
        #endif
        DisqueApp.main()
    }
}

#if DEBUG
/// Drives the real `Player` headlessly: auto-advance at track end, next/previous, shuffle, repeat, end of queue.
@MainActor
enum PlaybackSelfTest {
    static func run(paths: [String]) {
        let tracks: [Track] = paths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            guard let file = LibraryScanner.scanFile(at: url), let meta = MP3Reader.read(url: url) else { return nil }
            return TrackFactory.make(path: path, meta: meta, fileSize: file.size, modified: file.modified, dateAdded: Date())
        }
        guard tracks.count >= 3 else {
            print("need at least 3 mp3 files")
            exit(2)
        }
        let player = Player()
        Task { @MainActor in
            var failures = 0
            @MainActor func state() -> String {
                "[index=\(player.currentIndex.map(String.init) ?? "nil") \(player.currentTrack?.title ?? "-") playing=\(player.isPlaying) t=\(String(format: "%.2f", player.currentTime))/\(String(format: "%.2f", player.duration))]"
            }
            @MainActor func expect(_ label: String, timeout: Double = 6, _ condition: @MainActor () -> Bool) async {
                let start = Date()
                var ok = condition()
                while !ok && Date().timeIntervalSince(start) < timeout {
                    try? await Task.sleep(for: .milliseconds(50))
                    ok = condition()
                }
                let elapsed = String(format: "%.2fs", Date().timeIntervalSince(start))
                print("\(ok ? "PASS" : "FAIL")  \(label)  (\(elapsed)) \(state())")
                if !ok { failures += 1 }
            }

            while player.repeatMode != .off { player.cycleRepeat() }

            player.play(tracks, startAt: 0, shuffle: false, source: "Self test")
            await expect("starts playing track 1") { player.currentIndex == 0 && player.isPlaying }
            await expect("time advances") { player.currentTime > 0.3 }

            player.seek(to: player.duration - 1.5)
            await expect("seek lands near the end", timeout: 2) { player.currentTime >= player.duration - 2.2 }
            await expect("auto-advances to track 2") { player.currentIndex == 1 && player.isPlaying }
            await expect("track 2 plays from the start") { player.currentTime > 0.1 && player.currentTime < 3 }

            player.next()
            await expect("next() -> track 3", timeout: 1) { player.currentIndex == 2 }
            player.previous()
            await expect("previous() within 3s -> track 2", timeout: 1) { player.currentIndex == 1 }

            player.togglePlayPause()
            await expect("pause", timeout: 2) { !player.isPlaying }
            player.togglePlayPause()
            await expect("resume", timeout: 2) { player.isPlaying }

            player.toggleShuffle()
            await expect("shuffle keeps current track first", timeout: 1) { player.currentIndex == 0 && player.currentTrack?.id == tracks[1].id }
            await expect("shuffle keeps every track", timeout: 1) { Set(player.queue.map(\.track.id)) == Set(tracks.map(\.id)) && player.queue.count == tracks.count }
            player.toggleShuffle()
            await expect("unshuffle restores order", timeout: 1) { player.queue.map(\.track.id) == tracks.map(\.id) && player.currentIndex == 1 }

            player.jump(to: player.queue[tracks.count - 1].id)
            await expect("jump to last track", timeout: 2) { player.currentIndex == tracks.count - 1 && player.isPlaying }
            player.seek(to: player.duration - 1.5)
            await expect("end of queue rewinds to track 1, paused") { player.currentIndex == 0 && !player.isPlaying }

            player.addToQueue([tracks[0]])
            await expect("add to queue appends", timeout: 1) { player.queue.count == tracks.count + 1 }
            player.playNext([tracks[2]])
            await expect("play next inserts after current", timeout: 1) { player.queue[1].track.id == tracks[2].id }

            player.cycleRepeat() // all
            player.cycleRepeat() // one
            player.play(Array(tracks.prefix(2)), startAt: 0, shuffle: false)
            await expect("playing for repeat-one test") { player.isPlaying && player.currentTime > 0.2 }
            player.seek(to: player.duration - 1.5)
            await expect("seek lands near the end", timeout: 2) { player.currentTime >= player.duration - 2.2 }
            await expect("repeat-one restarts the same track") { player.currentIndex == 0 && player.isPlaying && player.currentTime < 1.5 }

            player.cycleRepeat() // off
            player.stop()
            print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
            exit(failures == 0 ? 0 : 1)
        }
    }
}
#endif
