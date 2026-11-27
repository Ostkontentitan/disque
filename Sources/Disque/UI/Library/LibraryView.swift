import SwiftUI

/// "My Library" page: title, tab strip (Albums · Artists · Tracks · Genres) and tab content.
struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "My Library", subtitle: summary)

            HStack(alignment: .top) {
                TabStrip(tabs: LibraryTab.allCases, title: \.title, selection: $router.libraryTab)
                Spacer()
                LibraryTabControls(tab: router.libraryTab)
                    .padding(.top, -6)
            }
            .padding(.horizontal, Theme.pagePadding)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.separator).frame(height: 1)
            }

            Group {
                if library.index.tracks.isEmpty {
                    LibraryEmptyContent()
                } else {
                    switch router.libraryTab {
                    case .albums: AlbumsTab()
                    case .artists: ArtistsTab()
                    case .tracks: TracksTab()
                    case .genres: GenresTab()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var summary: String {
        let index = library.index
        guard !index.tracks.isEmpty else { return "Your local music collection" }
        return [
            Formatters.count(index.albums.count, "album"),
            Formatters.count(index.artists.count, "artist"),
            Formatters.count(index.tracks.count, "track"),
            Formatters.longDuration(index.totalDuration),
        ].joined(separator: " · ")
    }
}

private struct LibraryTabControls: View {
    let tab: LibraryTab
    @Environment(LibraryStore.self) private var library
    @Environment(Player.self) private var player
    @AppStorage("albums.sort") private var albumSort: AlbumSort = .recentlyAdded
    @AppStorage("albums.genre") private var genreFilter = ""
    @AppStorage("tracks.sortKey") private var trackSort: TrackSortKey = .artist
    @AppStorage("tracks.ascending") private var trackAscending = true

    var body: some View {
        HStack(spacing: 10) {
            switch tab {
            case .albums:
                if !library.index.genres.isEmpty {
                    DropdownMenu(label: genreLabel, systemImage: "line.3.horizontal.decrease") {
                        Picker("Genre", selection: $genreFilter) {
                            Text("All Genres").tag("")
                            Divider()
                            ForEach(library.index.genres) { Text($0.name).tag($0.id) }
                        }
                        .pickerStyle(.inline)
                    }
                }
                DropdownMenu(label: albumSort.title, systemImage: "arrow.up.arrow.down") {
                    Picker("Sort by", selection: $albumSort) {
                        ForEach(AlbumSort.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
            case .tracks:
                DropdownMenu(label: trackSort.title, systemImage: "arrow.up.arrow.down") {
                    Picker("Sort by", selection: $trackSort) {
                        ForEach(TrackSortKey.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Picker("Order", selection: $trackAscending) {
                        Text("Ascending").tag(true)
                        Text("Descending").tag(false)
                    }
                    .pickerStyle(.inline)
                }
            case .artists, .genres:
                EmptyView()
            }
            if !library.index.tracks.isEmpty {
                Button {
                    player.play(library.index.tracks, shuffle: true, source: "My Library")
                } label: {
                    Label("Shuffle All", systemImage: "shuffle")
                        .font(.ui(12.5, .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private var genreLabel: String {
        genreFilter.isEmpty ? "All Genres" : (library.index.genresByID[genreFilter]?.name ?? "All Genres")
    }
}

private struct LibraryEmptyContent: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        if library.isScanning {
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text(library.scanTotal > 0 ? "Reading \(library.scanCompleted) of \(library.scanTotal) files…" : "Looking for music…")
                    .font(.ui(13))
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyStateView(
                systemImage: "music.note.house",
                title: "No music found",
                message: "None of your library folders contain MP3 files yet. Add another folder or drop one onto this window.",
                actionTitle: "Add Folder…"
            ) {
                library.presentAddFolderPanel()
            }
        }
    }
}

// MARK: - Tabs

private struct AlbumsTab: View {
    @Environment(LibraryStore.self) private var library
    @AppStorage("albums.sort") private var sort: AlbumSort = .recentlyAdded
    @AppStorage("albums.genre") private var genreFilter = ""

    var body: some View {
        let filtered = genreFilter.isEmpty
            ? library.index.albums
            : library.index.albums.filter { $0.genre?.searchKey == genreFilter }
        ScrollView {
            if filtered.isEmpty {
                EmptyStateView(systemImage: "square.stack", title: "No albums", message: "No albums match this filter.")
            } else {
                AlbumGrid(albums: sort.apply(filtered))
                    .padding(Theme.pagePadding)
            }
        }
    }
}

private struct ArtistsTab: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        ScrollView {
            ArtistGrid(artists: library.index.artists)
                .padding(Theme.pagePadding)
        }
    }
}

private struct GenresTab: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        ScrollView {
            if library.index.genres.isEmpty {
                EmptyStateView(systemImage: "guitars", title: "No genres", message: "Your files don't have genre tags yet.")
            } else {
                GenreGrid(genres: library.index.genres)
                    .padding(Theme.pagePadding)
            }
        }
    }
}

private struct TracksTab: View {
    @Environment(LibraryStore.self) private var library
    @Environment(Player.self) private var player
    @AppStorage("tracks.sortKey") private var sortKey: TrackSortKey = .artist
    @AppStorage("tracks.ascending") private var ascending = true
    @State private var sorted: [Track] = []

    private struct SortToken: Equatable {
        let revision: Int
        let key: TrackSortKey
        let ascending: Bool
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { offset, track in
                        TrackRow(track: track, number: offset + 1, layout: .table, context: sorted) {
                            player.play(sorted, startAt: offset, source: "My Library")
                        }
                    }
                } header: {
                    TrackListHeader(layout: .table, sortKey: $sortKey, ascending: $ascending)
                        .padding(.top, 8)
                        .background(Theme.background)
                }
            }
            .padding(.horizontal, Theme.pagePadding - 12)
            .padding(.bottom, 32)
        }
        .task(id: SortToken(revision: library.index.revision, key: sortKey, ascending: ascending)) {
            let tracks = library.index.tracks
            if sortKey == .artist && ascending {
                sorted = tracks
                return
            }
            let key = sortKey
            let order = ascending
            let result = await Task.detached(priority: .userInitiated) {
                TrackSortKey.sort(tracks, by: key, ascending: order)
            }.value
            if !Task.isCancelled { sorted = result }
        }
    }
}
