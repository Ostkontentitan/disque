import Foundation

/// `Disque --dump-metadata <files or folders…>` prints what the scanner sees. Handy for debugging tags.
enum MetadataDump {
    static func run(paths: [String]) {
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            var files: [ScanFile] = []
            for path in paths {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                    print("missing: \(path)")
                    continue
                }
                let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
                if isDirectory.boolValue {
                    files += LibraryScanner.enumerate(folders: [url.path])
                } else if let file = LibraryScanner.scanFile(at: url) {
                    files.append(file)
                }
            }

            let start = Date()
            var tracks: [Track] = []
            for file in files.sorted(by: { $0.path < $1.path }) {
                guard let track = await LibraryScanner.parse(file, previous: nil) else {
                    print("FAILED: \(file.path)")
                    continue
                }
                tracks.append(track)
                let artBytes = track.hasEmbeddedArtwork && track.format == "MP3" ? (MP3Reader.artwork(url: track.url)?.count ?? -1) : 0
                print("""
                \(track.fileName)
                  title=\(track.title) | artist=\(track.artist) | albumArtist=\(track.albumArtist ?? "-") | album=\(track.album)
                  track=\(track.trackNumber.map(String.init) ?? "-")/\(track.trackTotal.map(String.init) ?? "-") \
                disc=\(track.discNumber.map(String.init) ?? "-")/\(track.discTotal.map(String.init) ?? "-") \
                year=\(track.year.map(String.init) ?? "-") genre=\(track.genre ?? "-") compilation=\(track.isCompilation)
                  duration=\(Formatters.duration(track.duration)) (\(String(format: "%.2f", track.duration))s) \(track.qualityLabel) \
                channels=\(track.channels.map(String.init) ?? "-") artwork=\(track.hasEmbeddedArtwork) (\(artBytes) bytes)
                """)
            }
            let elapsed = Date().timeIntervalSince(start)
            let index = LibraryIndex.build(from: tracks, revision: 1)
            print("\n\(tracks.count) tracks parsed in \(String(format: "%.3f", elapsed))s")
            print("\(index.albums.count) albums · \(index.artists.count) artists · \(index.genres.count) genres\n")
            for album in index.albums {
                print("ALBUM [\(album.artist)] \(album.title) (\(album.year.map(String.init) ?? "-"), \(album.genre ?? "-")) — \(album.tracks.count) tracks, \(Formatters.longDuration(album.duration)), \(album.qualityLabel), discs=\(album.discCount), compilation=\(album.isCompilation), embeddedArt=\(album.artwork.embeddedPath != nil)")
            }
            for artist in index.artists {
                print("ARTIST \(artist.name): albums=\(artist.albums.count) appearsOn=\(artist.appearsOn.count) tracks=\(artist.tracks.count)")
            }
            semaphore.signal()
        }
        semaphore.wait()
    }
}
