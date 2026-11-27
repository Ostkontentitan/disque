import SwiftUI

struct SidebarView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WindowDragArea()
                .frame(height: 44)

            Wordmark()
                .padding(.horizontal, 22)
                .padding(.bottom, 26)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    SidebarRow(title: "My Library", systemImage: "square.stack.fill", item: .library)
                    SidebarRow(title: "Favorites", systemImage: "heart.fill", item: .favorites)
                    SidebarRow(title: "Recently Played", systemImage: "clock.arrow.circlepath", item: .history)

                    HStack {
                        Text("PLAYLISTS")
                            .font(.ui(11, .bold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.tertiaryText)
                        Spacer()
                        Button {
                            router.requestNewPlaylist()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.secondaryText)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .help("New Playlist")
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 30)
                    .padding(.bottom, 6)

                    if library.playlists.isEmpty {
                        Text("Create playlists to collect tracks from across your library.")
                            .font(.ui(12))
                            .foregroundStyle(Theme.tertiaryText)
                            .padding(.horizontal, 12)
                            .padding(.top, 2)
                    }
                    ForEach(library.playlists) { playlist in
                        SidebarRow(title: playlist.name, systemImage: "music.note.list", item: .playlist(playlist.id))
                            .contextMenu {
                                Button("Rename…") { router.renamePlaylist = playlist }
                                Button("Delete…", role: .destructive) { router.deletePlaylist = playlist }
                            }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)

            LibraryStatusFooter()
        }
        .background(Theme.sidebar)
    }
}

private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let item: SidebarItem
    @Environment(Router.self) private var router
    @State private var hovering = false

    var body: some View {
        let selected = router.sidebar == item && !router.isSearching
        Button {
            router.select(item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
                    .frame(width: 20)
                Text(title)
                    .font(.ui(13.5, selected ? .semibold : .medium))
                    .foregroundStyle(selected || hovering ? Theme.primaryText : Theme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Theme.selected : (hovering ? Theme.hover : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct LibraryStatusFooter: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if library.isScanning {
                VStack(alignment: .leading, spacing: 6) {
                    if library.scanTotal > 0 {
                        ProgressView(value: Double(library.scanCompleted), total: Double(max(library.scanTotal, 1)))
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                    }
                    Text(library.scanTotal > 0 ? "Reading \(library.scanCompleted) of \(library.scanTotal)…" : "Checking for changes…")
                        .font(.ui(11))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Formatters.count(library.index.tracks.count, "track"))
                        .font(.ui(12, .medium))
                        .foregroundStyle(Theme.secondaryText)
                    Text(Formatters.count(library.folders.count, "folder"))
                        .font(.ui(11))
                        .foregroundStyle(Theme.tertiaryText)
                }
                Spacer()
                CircleIconButton(systemImage: "folder.badge.plus", size: 30, iconSize: 12, help: "Add Music Folder…") {
                    library.presentAddFolderPanel()
                }
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(PressableStyle())
                .help("Settings")
            }
        }
        .padding(.horizontal, Theme.chromePadding)
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
    }
}

struct Wordmark: View {
    var body: some View {
        HStack(spacing: 10) {
            VinylMark(size: 24)
            Text("disque")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .tracking(-0.6)
                .foregroundStyle(Theme.primaryText)
        }
    }
}

/// Small record glyph used as the app mark.
struct VinylMark: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.96))
            ForEach(1..<4, id: \.self) { ring in
                Circle()
                    .stroke(Color.black.opacity(0.1), lineWidth: max(0.5, size * 0.012))
                    .padding(size * (0.06 + CGFloat(ring) * 0.055))
            }
            Circle().fill(Theme.accent).padding(size * 0.3)
            Circle().fill(Theme.sidebar).padding(size * 0.45)
        }
        .frame(width: size, height: size)
    }
}
