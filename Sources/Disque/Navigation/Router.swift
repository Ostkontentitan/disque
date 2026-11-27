import Foundation
import Observation

enum SidebarItem: Hashable {
    case library
    case favorites
    case history
    case playlist(UUID)
}

enum LibraryTab: String, CaseIterable, Identifiable {
    case albums, artists, tracks, genres

    var id: String { rawValue }

    var title: String {
        switch self {
        case .albums: "Albums"
        case .artists: "Artists"
        case .tracks: "Tracks"
        case .genres: "Genres"
        }
    }
}

enum FavoritesTab: String, CaseIterable, Identifiable {
    case albums, tracks, artists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .albums: "Albums"
        case .tracks: "Tracks"
        case .artists: "Artists"
        }
    }
}

enum Route: Hashable {
    case album(String)
    case artist(String)
    case genre(String)
}

struct PlaylistRequest: Identifiable {
    let id = UUID()
    let tracks: [Track]
}

/// Navigation state: sidebar section, pushed detail pages with back/forward history, search and panels.
@MainActor
@Observable
final class Router {
    private(set) var sidebar: SidebarItem = .library
    var libraryTab: LibraryTab = .albums
    var favoritesTab: FavoritesTab = .albums
    private(set) var stack: [Route] = []
    private(set) var forwardStack: [Route] = []
    var searchText = ""
    var showQueue = false
    private(set) var searchFocusToken = 0

    var newPlaylistRequest: PlaylistRequest?
    var renamePlaylist: Playlist?
    var deletePlaylist: Playlist?

    var currentRoute: Route? { stack.last }
    var isSearching: Bool { !searchText.trimmed.isEmpty }
    var canGoBack: Bool { !stack.isEmpty || isSearching }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func select(_ item: SidebarItem) {
        sidebar = item
        stack.removeAll()
        forwardStack.removeAll()
        searchText = ""
    }

    func push(_ route: Route) {
        guard stack.last != route else { return }
        stack.append(route)
        forwardStack.removeAll()
    }

    func back() {
        if let route = stack.popLast() {
            forwardStack.append(route)
        } else if isSearching {
            searchText = ""
        }
    }

    func goForward() {
        if let route = forwardStack.popLast() { stack.append(route) }
    }

    /// Typing a search query brings the search results to the front.
    func searchTextChanged() {
        if isSearching, !stack.isEmpty {
            stack.removeAll()
            forwardStack.removeAll()
        }
    }

    func focusSearch() {
        searchFocusToken += 1
    }

    func showAlbum(_ id: String) { push(.album(id)) }
    func showArtist(_ id: String) { push(.artist(id)) }
    func showGenre(_ id: String) { push(.genre(id)) }

    func requestNewPlaylist(with tracks: [Track] = []) {
        newPlaylistRequest = PlaylistRequest(tracks: tracks)
    }
}
