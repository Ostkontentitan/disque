import SwiftUI

struct GenreGrid: View {
    let genres: [Genre]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 250, maximum: 380), spacing: 22, alignment: .top)],
            alignment: .leading,
            spacing: 22
        ) {
            ForEach(genres) { genre in
                GenreTile(genre: genre)
            }
        }
    }
}

struct GenreTile: View {
    let genre: Genre
    @Environment(Router.self) private var router
    @State private var hovering = false

    var body: some View {
        let color = Theme.tileColor(seed: genre.name)
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [color, color.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))

            // Fanned covers peeking from the right edge.
            ZStack {
                ForEach(Array(genre.albums.prefix(3).enumerated().reversed()), id: \.offset) { offset, album in
                    ArtworkView(request: album.artwork, pixelSize: 200, cornerRadius: 4)
                        .frame(width: 74, height: 74)
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                        .rotationEffect(.degrees(Double(offset - 1) * 9 + (hovering ? Double(offset - 1) * 4 : 0)))
                        .offset(x: CGFloat(offset) * 26 - 26, y: CGFloat(abs(offset - 1)) * 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.trailing, 34)
            .animation(.snappy(duration: 0.25), value: hovering)

            VStack(alignment: .leading, spacing: 4) {
                Text(genre.name)
                    .font(.ui(19, .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(Formatters.count(genre.albums.count, "album")) · \(Formatters.count(genre.trackCount, "track"))")
                    .font(.ui(12, .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(18)
        }
        .frame(height: 124)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .brightness(hovering ? 0.04 : 0)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { router.showGenre(genre.id) }
    }
}

struct GenreDetailView: View {
    let genreID: String
    @Environment(LibraryStore.self) private var library
    @Environment(Player.self) private var player
    @AppStorage("genre.sort") private var sort: AlbumSort = .artist

    var body: some View {
        if let genre = library.index.genresByID[genreID] {
            let tracks = genre.albums.flatMap(\.tracks)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("GENRE")
                            .font(.ui(11, .bold))
                            .tracking(1.6)
                            .foregroundStyle(Theme.secondaryText)
                        Text(genre.name)
                            .font(.ui(46, .heavy))
                            .foregroundStyle(Theme.primaryText)
                        Text("\(Formatters.count(genre.albums.count, "album")) · \(Formatters.count(tracks.count, "track")) · \(Formatters.longDuration(tracks.reduce(0) { $0 + $1.duration }))")
                            .font(.ui(13))
                            .foregroundStyle(Theme.secondaryText)
                        HStack(spacing: 12) {
                            Button {
                                player.play(tracks, shuffle: false, source: genre.name)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                            }
                            .buttonStyle(PillButtonStyle())
                            Button {
                                player.play(tracks, shuffle: true, source: genre.name)
                            } label: {
                                Label("Shuffle", systemImage: "shuffle")
                            }
                            .buttonStyle(PillButtonStyle(prominent: false))
                            Spacer()
                            DropdownMenu(label: sort.title, systemImage: "arrow.up.arrow.down") {
                                Picker("Sort by", selection: $sort) {
                                    ForEach(AlbumSort.allCases) { Text($0.title).tag($0) }
                                }
                                .pickerStyle(.inline)
                            }
                        }
                        .padding(.top, 12)
                    }
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.top, 36)
                    .padding(.bottom, 32)
                    .background(alignment: .top) {
                        LinearGradient(colors: [Theme.tileColor(seed: genre.name).opacity(0.45), Theme.background], startPoint: .top, endPoint: .bottom)
                            .frame(height: 320)
                            .allowsHitTesting(false)
                    }

                    AlbumGrid(albums: sort.apply(genre.albums))
                        .padding(.horizontal, Theme.pagePadding)
                }
                .padding(.bottom, 48)
            }
        } else {
            EmptyStateView(systemImage: "guitars", title: "Genre not found", message: "No albums in your library use this genre anymore.")
        }
    }
}
