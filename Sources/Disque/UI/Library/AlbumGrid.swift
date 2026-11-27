import SwiftUI

struct AlbumGrid: View {
    let albums: [Album]
    var minimumWidth: CGFloat = 176

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimumWidth, maximum: 280), spacing: 28, alignment: .top)],
            alignment: .leading,
            spacing: 36
        ) {
            ForEach(albums) { album in
                AlbumCard(album: album)
            }
        }
    }
}

/// Horizontally scrolling row of albums (used for "More by" style sections).
struct AlbumRow: View {
    let albums: [Album]
    var cardWidth: CGFloat = 184

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 24) {
                ForEach(albums) { album in
                    AlbumCard(album: album).frame(width: cardWidth)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
        }
        .scrollIndicators(.never)
    }
}

struct AlbumCard: View {
    let album: Album
    var showsArtist = true

    @Environment(LibraryStore.self) private var library
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router
    @State private var hovering = false

    private var isCurrentAlbum: Bool {
        guard let id = player.currentTrackID else { return false }
        return album.tracks.contains { $0.id == id }
    }

    var body: some View {
        let current = isCurrentAlbum
        VStack(alignment: .leading, spacing: 10) {
            ArtworkView(request: album.artwork, pixelSize: 480, cornerRadius: 6)
                .shadow(color: Theme.shadow(hovering ? 0.45 : 0.25), radius: hovering ? 14 : 6, y: hovering ? 8 : 3)
                .overlay {
                    if hovering {
                        LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .bottom) {
                    if hovering {
                        HStack(spacing: 8) {
                            PlayCircleButton(size: 42, isPlaying: current && player.isPlaying) {
                                if current { player.togglePlayPause() } else { player.play(album.tracks, source: album.title) }
                            }
                            Spacer()
                            FavoriteButton(isFavorite: library.isFavorite(album), size: 16, inactiveColor: .white.opacity(0.85)) {
                                library.toggleFavorite(album)
                            }
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(.black.opacity(0.35)))
                            MoreMenuButton(size: 34) { AlbumMenuItems(album: album) }
                        }
                        .padding(10)
                        // Drawn over the darkened cover, so always use the light-on-dark control colors.
                        .environment(\.colorScheme, .dark)
                        .transition(.opacity)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if current {
                        EqualizerBars(isAnimating: player.isPlaying, color: .white, height: 11)
                            .padding(7)
                            .background(Circle().fill(Theme.accent))
                            .padding(8)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { router.showAlbum(album.id) }

            VStack(alignment: .leading, spacing: 3) {
                Text(album.title)
                    .font(.ui(13.5, .semibold))
                    .foregroundStyle(current ? Theme.accent : Theme.primaryText)
                    .lineLimit(1)
                    .onTapGesture { router.showAlbum(album.id) }
                if showsArtist {
                    if album.isCompilation || library.index.artistsByID[album.artistID] == nil {
                        Text(album.artist).font(.ui(12.5)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                    } else {
                        LinkText(text: album.artist, font: .ui(12.5)) { router.showArtist(album.artistID) }
                    }
                }
                Text(metaLine)
                    .font(.ui(11.5))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
            }
        }
        .onHover { value in
            withAnimation(.easeOut(duration: 0.15)) { hovering = value }
        }
        .contextMenu { AlbumMenuItems(album: album) }
    }

    private var metaLine: String {
        [album.year.map(String.init), album.shortQuality].compactMap { $0 }.joined(separator: " · ")
    }
}
