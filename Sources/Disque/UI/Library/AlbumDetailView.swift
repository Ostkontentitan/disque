import SwiftUI

struct AlbumDetailView: View {
    let albumID: String
    @Environment(LibraryStore.self) private var library

    var body: some View {
        if let album = library.index.albumsByID[albumID] {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AlbumHeader(album: album)
                    AlbumTrackList(album: album)
                        .padding(.horizontal, Theme.pagePadding - 12)
                    AlbumFooter(album: album)
                        .padding(.horizontal, Theme.pagePadding)
                        .padding(.top, 20)
                    MoreByArtist(album: album)
                        .padding(.top, 44)
                }
                .padding(.bottom, 48)
                .background(alignment: .top) { HeroBackdrop(request: album.artwork) }
            }
        } else {
            EmptyStateView(systemImage: "square.stack", title: "Album not found", message: "This album is no longer in your library.")
        }
    }
}

private struct AlbumHeader: View {
    let album: Album
    @Environment(LibraryStore.self) private var library
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router

    var body: some View {
        let isCurrent = album.tracks.contains { $0.id == player.currentTrackID }
        HStack(alignment: .bottom, spacing: 36) {
            ArtworkView(request: album.artwork, pixelSize: 720, cornerRadius: 8)
                .frame(width: Theme.heroArtworkSize, height: Theme.heroArtworkSize)
                .shadow(color: .black.opacity(0.55), radius: 28, y: 14)

            VStack(alignment: .leading, spacing: 10) {
                Text(album.isCompilation ? "COMPILATION" : (album.tracks.count <= 4 ? "EP" : "ALBUM"))
                    .font(.ui(11, .bold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.secondaryText)
                Text(album.title)
                    .font(.display(Theme.heroTitleSize, .heavy))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                if album.isCompilation || library.index.artistsByID[album.artistID] == nil {
                    Text(album.artist).font(.ui(17, .semibold)).foregroundStyle(Theme.primaryText.opacity(0.85))
                } else {
                    LinkText(text: album.artist, font: .ui(17, .semibold), color: Theme.primaryText.opacity(0.85)) {
                        router.showArtist(album.artistID)
                    }
                }
                HStack(spacing: 10) {
                    Text(meta).font(.ui(13)).foregroundStyle(Theme.secondaryText)
                    QualityBadge(text: album.qualityLabel)
                }
                HStack(spacing: 12) {
                    Button {
                        if isCurrent { player.togglePlayPause() } else { player.play(album.tracks, source: album.title) }
                    } label: {
                        Label(isCurrent && player.isPlaying ? "Pause" : "Play", systemImage: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                            .frame(minWidth: 64)
                    }
                    .buttonStyle(PillButtonStyle())
                    Button {
                        player.play(album.tracks, shuffle: true, source: album.title)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    CircleIconButton(
                        systemImage: library.isFavorite(album) ? "heart.fill" : "heart",
                        isActive: library.isFavorite(album),
                        help: library.isFavorite(album) ? "Remove from Favorites" : "Add to Favorites"
                    ) {
                        library.toggleFavorite(album)
                    }
                    MoreMenuButton { AlbumMenuItems(album: album) }
                }
                .padding(.top, 12)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 28)
        .padding(.bottom, 34)
    }

    private var meta: String {
        var parts: [String] = []
        if let year = album.year { parts.append(String(year)) }
        if let genre = album.genre { parts.append(genre) }
        parts.append(Formatters.count(album.tracks.count, "track"))
        parts.append(Formatters.longDuration(album.duration))
        return parts.joined(separator: " · ")
    }
}

private struct AlbumTrackList: View {
    let album: Album
    @Environment(Player.self) private var player

    var body: some View {
        let discs = Dictionary(grouping: album.tracks.enumerated(), by: { $0.element.discNumber ?? 1 })
            .sorted { $0.key < $1.key }
        VStack(spacing: 0) {
            TrackListHeader(layout: .album(albumArtist: album.artist))
                .padding(.bottom, 4)
            ForEach(discs, id: \.key) { disc, entries in
                if album.discCount > 1 {
                    HStack(spacing: 10) {
                        Image(systemName: "opticaldisc")
                            .font(.system(size: 13, weight: .medium))
                        Text("Disc \(disc)")
                            .font(.ui(13, .semibold))
                        Spacer()
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.top, disc == discs.first?.key ? 8 : 22)
                    .padding(.bottom, 6)
                }
                ForEach(entries, id: \.element.id) { offset, track in
                    TrackRow(
                        track: track,
                        number: track.trackNumber ?? (offset + 1),
                        layout: .album(albumArtist: album.artist),
                        context: album.tracks
                    ) {
                        player.play(album.tracks, startAt: offset, source: album.title)
                    }
                }
            }
        }
    }
}

private struct AlbumFooter: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary)
                .font(.ui(12.5))
                .foregroundStyle(Theme.tertiaryText)
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                LinkText(text: (album.directory as NSString).abbreviatingWithTildeInPath, font: .ui(12), color: Theme.tertiaryText) {
                    NSWorkspace.shared.activateFileViewerSelecting(album.tracks.prefix(1).map(\.url))
                }
                .help("Show in Finder")
            }
            .foregroundStyle(Theme.tertiaryText)
        }
    }

    private var summary: String {
        var parts: [String] = []
        if let year = album.year { parts.append("Released \(year)") }
        parts.append(Formatters.count(album.tracks.count, "track"))
        if album.discCount > 1 { parts.append(Formatters.count(album.discCount, "disc")) }
        parts.append(Formatters.longDuration(album.duration))
        parts.append(Formatters.fileSize(album.totalSize))
        return parts.joined(separator: " · ")
    }
}

private struct MoreByArtist: View {
    let album: Album
    @Environment(LibraryStore.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        if !album.isCompilation, let artist = library.index.artistsByID[album.artistID] {
            let others = (artist.albums + artist.appearsOn).filter { $0.id != album.id }
            if !others.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    SectionTitle(title: "More by \(artist.name)", action: ("See Artist", { router.showArtist(artist.id) }))
                        .padding(.horizontal, Theme.pagePadding)
                    AlbumRow(albums: others)
                }
            }
        }
    }
}
