import SwiftUI

struct PlayerBar: View {
    var body: some View {
        HStack(spacing: 0) {
            NowPlayingSummary()
                .frame(width: 330, alignment: .leading)
            Spacer(minLength: 16)
            VStack(spacing: 4) {
                TransportControls()
                Scrubber()
            }
            .frame(maxWidth: 640)
            Spacer(minLength: 16)
            PlayerBarTrailing()
                .frame(width: 330, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .frame(height: 90)
        .background(Theme.playerBar)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
    }
}

private struct NowPlayingSummary: View {
    @Environment(LibraryStore.self) private var library
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router

    var body: some View {
        if let track = player.currentTrack {
            let album = library.index.album(for: track)
            HStack(spacing: 14) {
                ArtworkView(request: library.index.artwork(for: track), pixelSize: 160, cornerRadius: 4)
                    .frame(width: 58, height: 58)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                    .onTapGesture { if let album { router.showAlbum(album.id) } }
                    .help("Go to Album")
                VStack(alignment: .leading, spacing: 4) {
                    LinkText(text: track.title, font: .ui(13.5, .semibold), color: Theme.primaryText) {
                        if let album { router.showAlbum(album.id) }
                    }
                    if let artist = library.index.artist(named: track.artist) {
                        LinkText(text: track.artist, font: .ui(12.5)) { router.showArtist(artist.id) }
                    } else {
                        Text(track.artist).font(.ui(12.5)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                    }
                }
                FavoriteButton(isFavorite: library.isFavorite(track), size: 14) {
                    library.toggleFavorite(track)
                }
                .padding(.leading, 4)
            }
        } else {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.field)
                    .frame(width: 58, height: 58)
                    .overlay(Image(systemName: "music.note").foregroundStyle(Theme.tertiaryText))
                Text("Nothing playing")
                    .font(.ui(13))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }
}

private struct TransportControls: View {
    @Environment(Player.self) private var player

    var body: some View {
        HStack(spacing: 20) {
            ControlButton(
                systemImage: "shuffle",
                size: 14,
                isActive: player.shuffleEnabled,
                help: player.shuffleEnabled ? "Shuffle On" : "Shuffle Off"
            ) {
                player.toggleShuffle()
            }
            ControlButton(systemImage: "backward.fill", size: 17, isEnabled: player.hasQueue, help: "Previous") {
                player.previous()
            }
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.black)
                    .offset(x: player.isPlaying ? 0 : 1.5)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.white))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .disabled(!player.hasQueue)
            .opacity(player.hasQueue ? 1 : 0.5)
            .help(player.isPlaying ? "Pause" : "Play")
            ControlButton(systemImage: "forward.fill", size: 17, isEnabled: player.hasQueue, help: "Next") {
                player.next()
            }
            ControlButton(
                systemImage: player.repeatMode == .one ? "repeat.1" : "repeat",
                size: 14,
                isActive: player.repeatMode != .off,
                help: ["Repeat Off", "Repeat All", "Repeat One"][player.repeatMode.rawValue]
            ) {
                player.cycleRepeat()
            }
        }
    }
}

/// Seek bar with elapsed / total time.
private struct Scrubber: View {
    @Environment(Player.self) private var player
    @State private var dragValue: Double?
    @State private var hovering = false

    var body: some View {
        let duration = max(player.duration, 0)
        let value = dragValue ?? player.currentTime
        HStack(spacing: 10) {
            Text(Formatters.duration(value))
                .frame(width: 44, alignment: .trailing)
            ThinSlider(
                value: duration > 0 ? min(value / duration, 1) : 0,
                isActive: hovering || dragValue != nil,
                onChange: { fraction in dragValue = fraction * duration },
                onCommit: { fraction in
                    player.seek(to: fraction * duration)
                    dragValue = nil
                }
            )
            .frame(height: 16)
            .onHover { hovering = $0 }
            .disabled(player.currentTrack == nil)
            Text(Formatters.duration(duration))
                .frame(width: 44, alignment: .leading)
        }
        .font(.ui(11).monospacedDigit())
        .foregroundStyle(Theme.tertiaryText)
    }
}

private struct PlayerBarTrailing: View {
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router
    @State private var hoveringVolume = false

    var body: some View {
        @Bindable var player = player
        HStack(spacing: 14) {
            if let track = player.currentTrack {
                QualityBadge(text: track.qualityLabel)
                    .help(track.fileName)
            }
            ControlButton(systemImage: "list.bullet", size: 14, isActive: router.showQueue, help: "Queue") {
                router.showQueue.toggle()
            }
            HStack(spacing: 6) {
                ControlButton(systemImage: volumeIcon, size: 13, help: player.isMuted ? "Unmute" : "Mute") {
                    player.toggleMute()
                }
                .frame(width: 28)
                ThinSlider(
                    value: player.isMuted ? 0 : player.volume,
                    isActive: hoveringVolume,
                    onChange: { value in
                        player.isMuted = false
                        player.volume = value
                    },
                    onCommit: { value in player.volume = value }
                )
                .frame(width: 96, height: 16)
                .onHover { hoveringVolume = $0 }
            }
        }
    }

    private var volumeIcon: String {
        if player.isMuted || player.volume == 0 { return "speaker.slash.fill" }
        if player.volume < 0.34 { return "speaker.wave.1.fill" }
        if player.volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

/// Minimal capsule slider with a knob that appears on hover.
struct ThinSlider: View {
    let value: Double
    var isActive: Bool
    let onChange: (Double) -> Void
    let onCommit: (Double) -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var dragging = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let fraction = min(max(value, 0), 1)
            let highlighted = (isActive || dragging) && isEnabled
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: highlighted ? 5 : 3.5)
                Capsule()
                    .fill(highlighted ? Theme.accent : Color.white.opacity(0.85))
                    .frame(width: width * fraction, height: highlighted ? 5 : 3.5)
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: width * fraction - 6)
                    .opacity(highlighted ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        dragging = true
                        onChange(min(max(gesture.location.x / width, 0), 1))
                    }
                    .onEnded { gesture in
                        dragging = false
                        onCommit(min(max(gesture.location.x / width, 0), 1))
                    }
            )
            .animation(.easeOut(duration: 0.12), value: highlighted)
        }
    }
}
