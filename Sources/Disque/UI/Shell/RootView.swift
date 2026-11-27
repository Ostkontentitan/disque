import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router
    @State private var isDropTargeted = false
    @AppStorage(Typeface.storageKey) private var typeface: Typeface = .system

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: 240)
                Rectangle()
                    .fill(Theme.separator)
                    .frame(width: 1)
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 0) {
                        TopBar()
                        ContentArea()
                    }
                    if router.showQueue {
                        QueuePanel()
                            .frame(width: 380)
                            .transition(.move(edge: .trailing))
                    }
                }
                .clipped()
                .background(Theme.background)
            }
            PlayerBar()
        }
        // Fonts are resolved when views are built, so rebuild the window contents on a typeface change.
        .id(typeface)
        .ignoresSafeArea()
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .frame(minWidth: 1100, minHeight: 700)
        .animation(.snappy(duration: 0.28), value: router.showQueue)
        .dropDestination(for: URL.self) { urls, _ in
            let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            guard !folders.isEmpty else { return false }
            library.addFolders(folders)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .overlay {
            if isDropTargeted { DropOverlay() }
        }
        .modifier(PlaylistDialogs())
        .task {
            player.library = library
            await library.start()
            player.restoreState(from: library)
        }
    }
}

private struct DropOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 14) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 52, weight: .light))
                Text("Drop folders to add them to your library")
                    .font(.ui(17, .semibold))
            }
            .foregroundStyle(.white)
            .padding(48)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Shows the current section, with pushed detail pages layered on top so the
/// underlying page keeps its scroll position when navigating back.
struct ContentArea: View {
    @Environment(LibraryStore.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        ZStack {
            root
                // When a sidebar click also pops a detail page, swap the section instantly so only
                // the detail page fades out (instead of three pages cross-fading at once).
                .id(RootKey(sidebar: router.sidebar, isSearching: router.isSearching))
                .transition(.identity)
                .opacity(router.stack.isEmpty ? 1 : 0)
                .allowsHitTesting(router.stack.isEmpty)
                .accessibilityHidden(!router.stack.isEmpty)

            if let route = router.currentRoute {
                detail(for: route)
                    .id(route)
                    .background(Theme.background)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: router.currentRoute)
    }

    private struct RootKey: Hashable {
        let sidebar: SidebarItem
        let isSearching: Bool
    }

    @ViewBuilder
    private var root: some View {
        if !library.hasLoaded {
            ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if library.folders.isEmpty {
            WelcomeView()
        } else if router.isSearching {
            SearchResultsView(query: router.searchText)
        } else {
            switch router.sidebar {
            case .library: LibraryView()
            case .favorites: FavoritesView()
            case .history: HistoryView()
            case .playlist(let id): PlaylistView(playlistID: id).id(id)
            }
        }
    }

    @ViewBuilder
    private func detail(for route: Route) -> some View {
        switch route {
        case .album(let id): AlbumDetailView(albumID: id)
        case .artist(let id): ArtistDetailView(artistID: id)
        case .genre(let id): GenreDetailView(genreID: id)
        }
    }
}

/// First-run screen when no folders are configured.
struct WelcomeView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        VStack(spacing: 22) {
            VinylMark(size: 112)
                .shadow(color: Theme.accent.opacity(0.35), radius: 40)
                .padding(.bottom, 8)
            Text("Your music, beautifully organised")
                .font(.display(30, .heavy))
                .foregroundStyle(Theme.primaryText)
            Text("Add the folders where you keep your MP3s. Disque reads their tags and artwork, groups them into albums and artists, and keeps everything in sync as files change.")
                .font(.ui(14))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .lineSpacing(3)
            HStack(spacing: 12) {
                Button {
                    library.presentAddFolderPanel()
                } label: {
                    Label("Add Music Folder…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(PillButtonStyle())
                if let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first {
                    Button {
                        library.addFolders([music])
                    } label: {
                        Text("Use ~/Music")
                    }
                    .buttonStyle(PillButtonStyle(prominent: false))
                }
            }
            .padding(.top, 8)
            Text("You can also drag a folder anywhere into this window.")
                .font(.ui(12))
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Alerts for creating, renaming and deleting playlists.
private struct PlaylistDialogs: ViewModifier {
    @Environment(LibraryStore.self) private var library
    @Environment(Router.self) private var router
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert("New Playlist", isPresented: Binding(
                get: { router.newPlaylistRequest != nil },
                set: { if !$0 { router.newPlaylistRequest = nil } }
            )) {
                TextField("Playlist name", text: $name)
                Button("Create") {
                    let request = router.newPlaylistRequest
                    let playlist = library.createPlaylist(name: name, tracks: request?.tracks ?? [])
                    router.newPlaylistRequest = nil
                    if request?.tracks.isEmpty ?? true { router.select(.playlist(playlist.id)) }
                }
                Button("Cancel", role: .cancel) { router.newPlaylistRequest = nil }
            } message: {
                if let count = router.newPlaylistRequest?.tracks.count, count > 0 {
                    Text("The playlist will start with \(Formatters.count(count, "track")).")
                }
            }
            .alert("Rename Playlist", isPresented: Binding(
                get: { router.renamePlaylist != nil },
                set: { if !$0 { router.renamePlaylist = nil } }
            )) {
                TextField("Playlist name", text: $name)
                Button("Rename") {
                    if let playlist = router.renamePlaylist { library.renamePlaylist(playlist.id, to: name) }
                    router.renamePlaylist = nil
                }
                Button("Cancel", role: .cancel) { router.renamePlaylist = nil }
            }
            .confirmationDialog(
                "Delete “\(router.deletePlaylist?.name ?? "")”?",
                isPresented: Binding(
                    get: { router.deletePlaylist != nil },
                    set: { if !$0 { router.deletePlaylist = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Playlist", role: .destructive) {
                    if let playlist = router.deletePlaylist {
                        if router.sidebar == .playlist(playlist.id) { router.select(.library) }
                        library.deletePlaylist(playlist.id)
                    }
                    router.deletePlaylist = nil
                }
            } message: {
                Text("The music files themselves are not affected.")
            }
            .onChange(of: router.newPlaylistRequest?.id) { _, value in
                if value != nil { name = "" }
            }
            .onChange(of: router.renamePlaylist?.id) { _, _ in
                name = router.renamePlaylist?.name ?? ""
            }
    }
}
