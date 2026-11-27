import SwiftUI

enum TrackRowLayout: Equatable {
    /// Album page: numbers, no artwork, artist shown only when it differs from the album artist.
    case album(albumArtist: String)
    /// Generic list: artwork, title + artist, album column.
    case list
    /// Library table: artwork, separate title / artist / album columns.
    case table
}

struct TrackRow: View {
    let track: Track
    let number: Int
    var layout: TrackRowLayout = .list
    var context: [Track] = []
    var onRemoveFromPlaylist: (() -> Void)?
    /// Optional extra column after the album (e.g. when the track was played).
    var detail: String?
    let onPlay: () -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router
    @State private var hovering = false

    private var showsArtwork: Bool { if case .album = layout { return false } else { return true } }

    var body: some View {
        let isCurrent = player.currentTrackID == track.id
        let isFavorite = library.isFavorite(track)
        HStack(spacing: 14) {
            leading(isCurrent: isCurrent)
                .frame(width: 28)

            if showsArtwork {
                ArtworkView(request: library.index.artwork(for: track), pixelSize: 96, cornerRadius: 3)
                    .frame(width: 40, height: 40)
            }

            titleBlock(isCurrent: isCurrent)
                .frame(maxWidth: .infinity, alignment: .leading)

            if layout == .table {
                artistLink
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if layout == .table || layout == .list {
                albumLink
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let detail {
                Text(detail)
                    .font(.ui(12.5))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .frame(width: TrackListHeader.detailWidth, alignment: .leading)
            }

            FavoriteButton(isFavorite: isFavorite, size: 13) { library.toggleFavorite(track) }
                .frame(width: 22)
                .opacity(hovering || isFavorite ? 1 : 0)

            Text(Formatters.duration(track.duration))
                .font(.ui(13).monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 48, alignment: .trailing)

            MoreMenuButton(size: 24, filled: false) {
                TrackMenuItems(track: track, context: context, onRemoveFromPlaylist: onRemoveFromPlaylist)
            }
            .frame(width: 22)
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .frame(height: showsArtwork ? 58 : 52)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hovering ? Theme.hover : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onPlay)
        .contextMenu {
            TrackMenuItems(track: track, context: context, onRemoveFromPlaylist: onRemoveFromPlaylist)
        }
    }

    @ViewBuilder
    private func leading(isCurrent: Bool) -> some View {
        if hovering {
            Button {
                if isCurrent { player.togglePlayPause() } else { onPlay() }
            } label: {
                Image(systemName: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        } else if isCurrent {
            EqualizerBars(isAnimating: player.isPlaying)
        } else {
            Text("\(number)")
                .font(.ui(13).monospacedDigit())
                .foregroundStyle(Theme.tertiaryText)
        }
    }

    @ViewBuilder
    private func titleBlock(isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(track.title)
                .font(.ui(13.5, .medium))
                .foregroundStyle(isCurrent ? Theme.accent : Theme.primaryText)
                .lineLimit(1)
            switch layout {
            case .album(let albumArtist):
                if Artist.makeID(albumArtist) != Artist.makeID(track.artist) { artistLink }
            case .list:
                artistLink
            case .table:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var artistLink: some View {
        if let artist = library.index.artist(named: track.artist) {
            LinkText(text: track.artist, font: .ui(12.5)) { router.showArtist(artist.id) }
        } else {
            Text(track.artist).font(.ui(12.5)).foregroundStyle(Theme.secondaryText).lineLimit(1)
        }
    }

    @ViewBuilder
    private var albumLink: some View {
        if let album = library.index.album(for: track) {
            LinkText(text: track.album, font: .ui(12.5)) { router.showAlbum(album.id) }
        } else {
            Text(track.album).font(.ui(12.5)).foregroundStyle(Theme.secondaryText).lineLimit(1)
        }
    }
}

/// Column header matching `TrackRow` layouts.
struct TrackListHeader: View {
    var layout: TrackRowLayout = .list
    var sortKey: Binding<TrackSortKey>?
    var ascending: Binding<Bool>?
    /// Title of the optional `TrackRow.detail` column.
    var detailTitle: String?

    static let detailWidth: CGFloat = 120

    private var showsArtwork: Bool { if case .album = layout { return false } else { return true } }

    var body: some View {
        HStack(spacing: 14) {
            Text("#").frame(width: 28)
            if showsArtwork { Color.clear.frame(width: 40, height: 1) }
            column("TITLE", .title).frame(maxWidth: .infinity, alignment: .leading)
            if layout == .table {
                column("ARTIST", .artist).frame(maxWidth: .infinity, alignment: .leading)
            }
            if layout == .table || layout == .list {
                column("ALBUM", .album).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let detailTitle {
                Text(detailTitle).frame(width: Self.detailWidth, alignment: .leading)
            }
            Color.clear.frame(width: 22, height: 1)
            column(nil, .duration).frame(width: 48, alignment: .trailing)
            Color.clear.frame(width: 22, height: 1)
        }
        .font(.ui(11, .semibold))
        .tracking(1)
        .foregroundStyle(Theme.tertiaryText)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
    }

    @ViewBuilder
    private func column(_ title: String?, _ key: TrackSortKey) -> some View {
        let label = HStack(spacing: 4) {
            if let title { Text(title) } else { Image(systemName: "clock").font(.system(size: 11, weight: .semibold)) }
            if let sortKey, let ascending, sortKey.wrappedValue == key {
                Image(systemName: ascending.wrappedValue ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .heavy))
            }
        }
        if let sortKey, let ascending {
            Button {
                if sortKey.wrappedValue == key {
                    ascending.wrappedValue.toggle()
                } else {
                    sortKey.wrappedValue = key
                    ascending.wrappedValue = key != .recentlyAdded
                }
            } label: {
                label.foregroundStyle(sortKey.wrappedValue == key ? Theme.secondaryText : Theme.tertiaryText)
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }
}

/// Simple vertical list of tracks with consistent playback behaviour.
struct TrackList: View {
    let tracks: [Track]
    var layout: TrackRowLayout = .list
    var source: String?

    @Environment(Player.self) private var player

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.offset) { offset, track in
                TrackRow(track: track, number: offset + 1, layout: layout, context: tracks) {
                    player.play(tracks, startAt: offset, source: source)
                }
            }
        }
    }
}
