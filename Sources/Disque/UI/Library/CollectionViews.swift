import SwiftUI

// MARK: - Favorites

struct FavoritesView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(Router.self) private var router
    @Environment(Player.self) private var player

    var body: some View {
        @Bindable var router = router
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Favorites", subtitle: summary)

            HStack(alignment: .top) {
                TabStrip(tabs: FavoritesTab.allCases, title: \.title, selection: $router.favoritesTab)
                Spacer()
                if router.favoritesTab == .tracks, !library.favoriteTrackList.isEmpty {
                    Button {
                        player.play(library.favoriteTrackList, shuffle: true, source: "Favorites")
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.ui(12.5, .semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .background(Capsule().fill(Theme.accent))
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.top, -6)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }

            ScrollView {
                switch router.favoritesTab {
                case .albums:
                    let albums = library.favoriteAlbumList
                    if albums.isEmpty {
                        emptyState("No favorite albums yet", "Click the heart on any album to keep it here.")
                    } else {
                        AlbumGrid(albums: albums).padding(Theme.pagePadding)
                    }
                case .tracks:
                    let tracks = library.favoriteTrackList
                    if tracks.isEmpty {
                        emptyState("No favorite tracks yet", "Hover over a track and click its heart to add it here.")
                    } else {
                        VStack(spacing: 0) {
                            TrackListHeader(layout: .list)
                            TrackList(tracks: tracks, layout: .list, source: "Favorites")
                        }
                        .padding(.horizontal, Theme.pagePadding - 12)
                        .padding(.vertical, 16)
                    }
                case .artists:
                    let artists = library.favoriteArtistList
                    if artists.isEmpty {
                        emptyState("No favorite artists yet", "Open an artist and click the heart to follow them here.")
                    } else {
                        ArtistGrid(artists: artists).padding(Theme.pagePadding)
                    }
                }
            }
        }
    }

    private func emptyState(_ title: String, _ message: String) -> some View {
        EmptyStateView(systemImage: "heart", title: title, message: message)
            .padding(.top, 60)
    }

    private var summary: String {
        [
            Formatters.count(library.favoriteAlbumList.count, "album"),
            Formatters.count(library.favoriteTrackList.count, "track"),
            Formatters.count(library.favoriteArtistList.count, "artist"),
        ].joined(separator: " · ")
    }
}

// MARK: - History

struct HistoryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(Player.self) private var player

    var body: some View {
        let entries = library.history.compactMap { entry in library.index.tracksByID[entry.path].map { (entry, $0) } }
        let tracks = entries.map(\.1)
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Recently Played", subtitle: entries.isEmpty ? nil : Formatters.count(entries.count, "play")) {
                if !entries.isEmpty {
                    Button("Clear History") { library.clearHistory() }
                        .buttonStyle(PillButtonStyle(prominent: false))
                }
            }
            if entries.isEmpty {
                EmptyStateView(systemImage: "clock.arrow.circlepath", title: "Nothing played yet", message: "Tracks you play will show up here.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        TrackListHeader(layout: .list, detailTitle: "PLAYED")
                        ForEach(Array(entries.enumerated()), id: \.element.0.id) { offset, item in
                            TrackRow(
                                track: item.1,
                                number: offset + 1,
                                layout: .list,
                                context: tracks,
                                detail: Formatters.relativeDate(item.0.date)
                            ) {
                                player.play(tracks, startAt: offset, source: "Recently Played")
                            }
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding - 12)
                    .padding(.bottom, 32)
                }
            }
        }
    }
}

// MARK: - Playlists

struct PlaylistView: View {
    let playlistID: UUID
    @Environment(LibraryStore.self) private var library
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router

    var body: some View {
        if let playlist = library.playlist(playlistID) {
            let entries: [(offset: Int, track: Track)] = playlist.trackPaths.enumerated().compactMap { offset, path in
                library.index.tracksByID[path].map { (offset, $0) }
            }
            let tracks = entries.map(\.track)
            let covers = uniqueArtwork(for: tracks)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .bottom, spacing: 36) {
                        MosaicArtwork(requests: covers, cornerRadius: 8, seed: playlist.name)
                            .frame(width: Theme.heroArtworkSize, height: Theme.heroArtworkSize)
                            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("PLAYLIST")
                                .font(.ui(11, .bold))
                                .tracking(1.6)
                                .foregroundStyle(Theme.secondaryText)
                            Text(playlist.name)
                                .font(.display(Theme.heroTitleSize, .heavy))
                                .foregroundStyle(Theme.primaryText)
                                .lineLimit(2)
                                .minimumScaleFactor(0.5)
                            Text("\(Formatters.count(tracks.count, "track")) · \(Formatters.longDuration(tracks.reduce(0) { $0 + $1.duration })) · Updated \(Formatters.relativeDate(playlist.modified).lowercased())")
                                .font(.ui(13))
                                .foregroundStyle(Theme.secondaryText)
                            HStack(spacing: 12) {
                                Button {
                                    player.play(tracks, shuffle: false, source: playlist.name)
                                } label: {
                                    Label("Play", systemImage: "play.fill")
                                }
                                .buttonStyle(PillButtonStyle())
                                .disabled(tracks.isEmpty)
                                Button {
                                    player.play(tracks, shuffle: true, source: playlist.name)
                                } label: {
                                    Label("Shuffle", systemImage: "shuffle")
                                }
                                .buttonStyle(PillButtonStyle(prominent: false))
                                .disabled(tracks.isEmpty)
                                MoreMenuButton {
                                    Button("Rename…") { router.renamePlaylist = playlist }
                                    Button("Add to Queue") { player.addToQueue(tracks) }
                                    Divider()
                                    Button("Delete Playlist…", role: .destructive) { router.deletePlaylist = playlist }
                                }
                            }
                            .padding(.top, 12)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.top, 28)
                    .padding(.bottom, 34)

                    if entries.isEmpty {
                        EmptyStateView(
                            systemImage: "music.note.list",
                            title: "This playlist is empty",
                            message: "Right-click any track or album and choose “Add to Playlist” to fill it."
                        )
                        .padding(.top, 20)
                    } else {
                        VStack(spacing: 0) {
                            TrackListHeader(layout: .list)
                            LazyVStack(spacing: 0) {
                                ForEach(Array(entries.enumerated()), id: \.offset) { position, entry in
                                    TrackRow(
                                        track: entry.track,
                                        number: position + 1,
                                        layout: .list,
                                        context: tracks,
                                        onRemoveFromPlaylist: { library.removeTrack(at: entry.offset, fromPlaylist: playlist.id) }
                                    ) {
                                        player.play(tracks, startAt: position, source: playlist.name)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, Theme.pagePadding - 12)
                    }
                }
                .padding(.bottom, 48)
                .background(alignment: .top) { HeroBackdrop(request: covers.first) }
            }
        } else {
            EmptyStateView(systemImage: "music.note.list", title: "Playlist not found", message: "This playlist was deleted.")
        }
    }

    private func uniqueArtwork(for tracks: [Track]) -> [ArtworkRequest] {
        var seen = Set<String>()
        var result: [ArtworkRequest] = []
        for track in tracks {
            let request = library.index.artwork(for: track)
            if seen.insert(request.key).inserted { result.append(request) }
            if result.count == 4 { break }
        }
        return result
    }
}

// MARK: - Search

struct SearchResultsView: View {
    let query: String
    @Environment(LibraryStore.self) private var library
    @State private var results = SearchResults()
    @State private var hasSearched = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                PageHeader(title: "Results for “\(query.trimmed)”", subtitle: hasSearched ? summary : " ")
                    .padding(.bottom, -20)

                if hasSearched && results.isEmpty {
                    EmptyStateView(systemImage: "magnifyingglass", title: "No results", message: "Nothing in your library matches “\(query.trimmed)”. Try another spelling or fewer words.")
                        .padding(.top, 40)
                }

                if !results.artists.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionTitle(title: "Artists", subtitle: "\(results.artists.count)")
                            .padding(.horizontal, Theme.pagePadding)
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 24) {
                                ForEach(results.artists.prefix(20)) { artist in
                                    ArtistCard(artist: artist).frame(width: 156)
                                }
                            }
                            .padding(.horizontal, Theme.pagePadding)
                        }
                        .scrollIndicators(.never)
                    }
                }

                if !results.albums.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionTitle(title: "Albums", subtitle: "\(results.albums.count)")
                        AlbumGrid(albums: Array(results.albums.prefix(30)))
                    }
                    .padding(.horizontal, Theme.pagePadding)
                }

                if !results.tracks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Tracks", subtitle: "\(results.tracks.count)")
                            .padding(.horizontal, Theme.pagePadding)
                        VStack(spacing: 0) {
                            TrackListHeader(layout: .list)
                            TrackList(tracks: Array(results.tracks.prefix(100)), layout: .list, source: "Search")
                        }
                        .padding(.horizontal, Theme.pagePadding - 12)
                    }
                }
            }
            .padding(.bottom, 48)
        }
        .task(id: "\(query)#\(library.index.revision)") {
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            let index = library.index
            let text = query
            let computed = await Task.detached(priority: .userInitiated) {
                SearchResults.compute(query: text, in: index)
            }.value
            guard !Task.isCancelled else { return }
            results = computed
            hasSearched = true
        }
    }

    private var summary: String {
        [
            Formatters.count(results.artists.count, "artist"),
            Formatters.count(results.albums.count, "album"),
            Formatters.count(results.tracks.count, "track"),
        ].joined(separator: " · ")
    }
}
