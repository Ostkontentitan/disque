import SwiftUI

struct AddToPlaylistMenu: View {
    let tracks: [Track]
    @Environment(LibraryStore.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        Menu {
            Button {
                router.requestNewPlaylist(with: tracks)
            } label: {
                Label("New Playlist…", systemImage: "plus")
            }
            if !library.playlists.isEmpty { Divider() }
            ForEach(library.playlists) { playlist in
                Button(playlist.name) { library.addTracks(tracks, toPlaylist: playlist.id) }
            }
        } label: {
            Label("Add to Playlist", systemImage: "music.note.list")
        }
    }
}

struct TrackMenuItems: View {
    let track: Track
    var context: [Track] = []
    var onRemoveFromPlaylist: (() -> Void)?
    @Environment(LibraryStore.self) private var library
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router

    var body: some View {
        Button {
            if let index = context.firstIndex(of: track) {
                player.play(context, startAt: index)
            } else {
                player.play([track])
            }
        } label: {
            Label("Play", systemImage: "play")
        }
        Button {
            player.playNext([track])
        } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        Button {
            player.addToQueue([track])
        } label: {
            Label("Add to Queue", systemImage: "text.badge.plus")
        }
        Divider()
        AddToPlaylistMenu(tracks: [track])
        if let onRemoveFromPlaylist {
            Button(role: .destructive, action: onRemoveFromPlaylist) {
                Label("Remove from Playlist", systemImage: "minus.circle")
            }
        }
        Divider()
        Button {
            library.toggleFavorite(track)
        } label: {
            Label(library.isFavorite(track) ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: library.isFavorite(track) ? "heart.slash" : "heart")
        }
        if let album = library.index.album(for: track) {
            Button {
                router.showAlbum(album.id)
            } label: {
                Label("Go to Album", systemImage: "square.stack")
            }
        }
        if let artist = library.index.artist(named: track.artist) ?? library.index.album(for: track).flatMap({ library.index.artistsByID[$0.artistID] }) {
            Button {
                router.showArtist(artist.id)
            } label: {
                Label("Go to Artist", systemImage: "music.mic")
            }
        }
        Divider()
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([track.url])
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }
    }
}

struct AlbumMenuItems: View {
    let album: Album
    @Environment(LibraryStore.self) private var library
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router

    var body: some View {
        Button {
            player.play(album.tracks, shuffle: false, source: album.title)
        } label: {
            Label("Play", systemImage: "play")
        }
        Button {
            player.play(album.tracks, shuffle: true, source: album.title)
        } label: {
            Label("Shuffle", systemImage: "shuffle")
        }
        Button {
            player.playNext(album.tracks)
        } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        Button {
            player.addToQueue(album.tracks)
        } label: {
            Label("Add to Queue", systemImage: "text.badge.plus")
        }
        Divider()
        AddToPlaylistMenu(tracks: album.tracks)
        Button {
            library.toggleFavorite(album)
        } label: {
            Label(library.isFavorite(album) ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: library.isFavorite(album) ? "heart.slash" : "heart")
        }
        Divider()
        if !album.isCompilation, library.index.artistsByID[album.artistID] != nil {
            Button {
                router.showArtist(album.artistID)
            } label: {
                Label("Go to Artist", systemImage: "music.mic")
            }
        }
        Button {
            NSWorkspace.shared.activateFileViewerSelecting(album.tracks.prefix(1).map(\.url))
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }
    }
}

struct ArtistMenuItems: View {
    let artist: Artist
    @Environment(LibraryStore.self) private var library
    @Environment(Player.self) private var player

    var body: some View {
        Button {
            player.play(artist.tracks, shuffle: false, source: artist.name)
        } label: {
            Label("Play", systemImage: "play")
        }
        Button {
            player.play(artist.tracks, shuffle: true, source: artist.name)
        } label: {
            Label("Shuffle", systemImage: "shuffle")
        }
        Button {
            player.addToQueue(artist.tracks)
        } label: {
            Label("Add to Queue", systemImage: "text.badge.plus")
        }
        Divider()
        Button {
            library.toggleFavorite(artist)
        } label: {
            Label(library.isFavorite(artist) ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: library.isFavorite(artist) ? "heart.slash" : "heart")
        }
    }
}
