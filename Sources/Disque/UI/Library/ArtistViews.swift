import SwiftUI

struct ArtistGrid: View {
    let artists: [Artist]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 156, maximum: 220), spacing: 28, alignment: .top)],
            alignment: .leading,
            spacing: 32
        ) {
            ForEach(artists) { artist in
                ArtistCard(artist: artist)
            }
        }
    }
}

struct ArtistCard: View {
    let artist: Artist
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 12) {
            ArtworkView(request: artist.artwork, pixelSize: 400, circular: true, placeholderText: artist.albums.isEmpty ? artist.name : nil)
                .shadow(color: .black.opacity(hovering ? 0.45 : 0.25), radius: hovering ? 14 : 6, y: hovering ? 8 : 3)
                .overlay(alignment: .bottomTrailing) {
                    if hovering {
                        PlayCircleButton(size: 42) {
                            player.play(artist.tracks, source: artist.name)
                        }
                        .padding(4)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .contentShape(Circle())
                .onTapGesture { router.showArtist(artist.id) }

            VStack(spacing: 3) {
                Text(artist.name)
                    .font(.ui(13.5, .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.ui(12))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .onHover { value in withAnimation(.easeOut(duration: 0.15)) { hovering = value } }
        .contextMenu { ArtistMenuItems(artist: artist) }
    }

    private var subtitle: String {
        if artist.albums.isEmpty { return "Appears on \(Formatters.count(artist.appearsOn.count, "album"))" }
        return Formatters.count(artist.albums.count, "album")
    }
}

struct ArtistDetailView: View {
    let artistID: String
    @Environment(LibraryStore.self) private var library
    @Environment(Player.self) private var player
    @State private var showAllTracks = false

    var body: some View {
        if let artist = library.index.artistsByID[artistID] {
            ScrollView {
                VStack(alignment: .leading, spacing: 44) {
                    header(artist)

                    if !artist.tracks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle(
                                title: "Tracks",
                                subtitle: Formatters.count(artist.tracks.count, "track"),
                                action: artist.tracks.count > 8 ? (showAllTracks ? "Show Less" : "Show All", { withAnimation { showAllTracks.toggle() } }) : nil
                            )
                            .padding(.horizontal, Theme.pagePadding)
                            TrackList(tracks: Array(artist.tracks.prefix(showAllTracks ? artist.tracks.count : 8)), layout: .list, source: artist.name)
                                .padding(.horizontal, Theme.pagePadding - 12)
                        }
                    }

                    if !artist.albums.isEmpty {
                        VStack(alignment: .leading, spacing: 18) {
                            SectionTitle(title: "Albums", subtitle: "\(artist.albums.count)")
                            AlbumGrid(albums: artist.albums, minimumWidth: 168)
                        }
                        .padding(.horizontal, Theme.pagePadding)
                    }

                    if !artist.appearsOn.isEmpty {
                        VStack(alignment: .leading, spacing: 18) {
                            SectionTitle(title: "Appears On", subtitle: "\(artist.appearsOn.count)")
                            AlbumGrid(albums: artist.appearsOn, minimumWidth: 168)
                        }
                        .padding(.horizontal, Theme.pagePadding)
                    }
                }
                .padding(.bottom, 48)
                .background(alignment: .top) { HeroBackdrop(request: artist.artwork, height: 460) }
            }
        } else {
            EmptyStateView(systemImage: "music.mic", title: "Artist not found", message: "This artist is no longer in your library.")
        }
    }

    private func header(_ artist: Artist) -> some View {
        HStack(alignment: .center, spacing: 36) {
            ArtworkView(request: artist.artwork, pixelSize: 600, circular: true, placeholderText: artist.albums.isEmpty ? artist.name : nil)
                .frame(width: 220, height: 220)
                .shadow(color: .black.opacity(0.5), radius: 24, y: 12)

            VStack(alignment: .leading, spacing: 10) {
                Text("ARTIST")
                    .font(.ui(11, .bold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.secondaryText)
                Text(artist.name)
                    .font(.ui(46, .heavy))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                Text(stats(artist))
                    .font(.ui(13))
                    .foregroundStyle(Theme.secondaryText)
                HStack(spacing: 12) {
                    Button {
                        player.play(artist.tracks, shuffle: false, source: artist.name)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(PillButtonStyle())
                    Button {
                        player.play(artist.tracks, shuffle: true, source: artist.name)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    CircleIconButton(
                        systemImage: library.isFavorite(artist) ? "heart.fill" : "heart",
                        isActive: library.isFavorite(artist),
                        help: library.isFavorite(artist) ? "Remove from Favorites" : "Add to Favorites"
                    ) {
                        library.toggleFavorite(artist)
                    }
                    MoreMenuButton { ArtistMenuItems(artist: artist) }
                }
                .padding(.top, 10)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 28)
    }

    private func stats(_ artist: Artist) -> String {
        var parts: [String] = []
        if !artist.albums.isEmpty { parts.append(Formatters.count(artist.albums.count, "album")) }
        parts.append(Formatters.count(artist.tracks.count, "track"))
        parts.append(Formatters.longDuration(artist.tracks.reduce(0) { $0 + $1.duration }))
        return parts.joined(separator: " · ")
    }
}
