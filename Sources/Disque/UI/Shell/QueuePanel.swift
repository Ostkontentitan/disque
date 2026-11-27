import SwiftUI

struct QueuePanel: View {
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Queue")
                        .font(.ui(22, .bold))
                        .foregroundStyle(Theme.primaryText)
                    if let source = player.sourceName {
                        Text("Playing from \(source)")
                            .font(.ui(12))
                            .foregroundStyle(Theme.tertiaryText)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if !player.upcoming.isEmpty {
                    Button("Clear") { player.clearUpcoming() }
                        .buttonStyle(.plain)
                        .font(.ui(12.5, .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.trailing, 6)
                }
                CircleIconButton(systemImage: "xmark", size: 28, iconSize: 11, help: "Close") {
                    router.showQueue = false
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            if player.queue.isEmpty {
                EmptyStateView(
                    systemImage: "list.bullet",
                    title: "Queue is empty",
                    message: "Play an album or right-click a track and choose “Add to Queue”."
                )
            } else {
                List {
                    if let entry = player.currentEntry {
                        Section {
                            QueueRow(entry: entry, isCurrent: true)
                                .queueRowStyle()
                        } header: {
                            QueueSectionHeader(title: "Now Playing")
                        }
                    }
                    Section {
                        if player.upcoming.isEmpty {
                            Text(player.repeatMode == .off ? "Nothing up next." : "The queue repeats from the start.")
                                .font(.ui(12.5))
                                .foregroundStyle(Theme.tertiaryText)
                                .padding(.vertical, 8)
                                .queueRowStyle()
                        }
                        ForEach(player.upcoming) { entry in
                            QueueRow(entry: entry, isCurrent: false)
                                .queueRowStyle()
                        }
                        .onMove { source, destination in
                            player.moveUpcoming(from: source, to: destination)
                        }
                    } header: {
                        QueueSectionHeader(title: "Next Up", detail: upcomingSummary)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 10)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Theme.elevated)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.separator).frame(width: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 30, x: -12)
    }

    private var upcomingSummary: String? {
        let upcoming = player.upcoming
        guard !upcoming.isEmpty else { return nil }
        return "\(Formatters.count(upcoming.count, "track")) · \(Formatters.longDuration(upcoming.reduce(0) { $0 + $1.track.duration }))"
    }
}

private struct QueueSectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.ui(11, .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.tertiaryText)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.ui(11))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

private struct QueueRow: View {
    let entry: QueueEntry
    let isCurrent: Bool
    @Environment(LibraryStore.self) private var library
    @Environment(Player.self) private var player
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(request: library.index.artwork(for: entry.track), pixelSize: 96, cornerRadius: 3)
                .frame(width: 40, height: 40)
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 3).fill(.black.opacity(0.45))
                        EqualizerBars(isAnimating: player.isPlaying, color: .white)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.track.title)
                    .font(.ui(13, .medium))
                    .foregroundStyle(isCurrent ? Theme.accent : Theme.primaryText)
                    .lineLimit(1)
                Text(entry.track.artist)
                    .font(.ui(12))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if hovering && !isCurrent {
                Button {
                    player.remove(entry.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .help("Remove from Queue")
            } else {
                Text(Formatters.duration(entry.track.duration))
                    .font(.ui(12).monospacedDigit())
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) {
            if !isCurrent { player.jump(to: entry.id) }
        }
        .contextMenu {
            if !isCurrent {
                Button("Play Now") { player.jump(to: entry.id) }
                Button("Remove from Queue") { player.remove(entry.id) }
            }
        }
    }
}

private extension View {
    func queueRowStyle() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
