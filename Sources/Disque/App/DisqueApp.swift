import SwiftUI

struct DisqueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = LibraryStore()
    @State private var player = Player()
    @State private var router = Router()

    var body: some Scene {
        Window("Disque", id: "main") {
            RootView()
                .environment(library)
                .environment(player)
                .environment(router)
                .onAppear {
                    appDelegate.player = player
                    appDelegate.library = library
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1380, height: 880)
        .commands {
            AppCommands(library: library, player: player, router: router)
        }

        Settings {
            SettingsView()
                .environment(library)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var player: Player?
    weak var library: LibraryStore?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()

        // Space toggles playback unless a text field is being edited.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
            guard event.keyCode == 49, modifiers.isEmpty else { return event }
            if event.window?.firstResponder is NSText { return event }
            guard event.window?.isKeyWindow == true, event.window?.attachedSheet == nil else { return event }
            MainActor.assumeIsolated { self?.player?.togglePlayPause() }
            return nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        player?.saveState()
        library?.saveStateNow(synchronously: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }
}

struct AppCommands: Commands {
    let library: LibraryStore
    let player: Player
    let router: Router

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Playlist…") { router.requestNewPlaylist() }
                .keyboardShortcut("n")
            Divider()
            Button("Add Music Folder…") { library.presentAddFolderPanel() }
                .keyboardShortcut("o")
            Button("Rescan Library") { library.rescan() }
                .keyboardShortcut("r")
        }

        CommandGroup(after: .textEditing) {
            Button("Search Library") { router.focusSearch() }
                .keyboardShortcut("f")
        }

        CommandGroup(before: .sidebar) {
            Button("My Library") { router.select(.library) }
                .keyboardShortcut("1")
            Button("Favorites") { router.select(.favorites) }
                .keyboardShortcut("2")
            Button("Recently Played") { router.select(.history) }
                .keyboardShortcut("3")
            Divider()
            Button("Back") { router.back() }
                .keyboardShortcut("[")
            Button("Forward") { router.goForward() }
                .keyboardShortcut("]")
            Divider()
            Button(router.showQueue ? "Hide Queue" : "Show Queue") { router.showQueue.toggle() }
                .keyboardShortcut("u", modifiers: [.command, .option])
            Divider()
        }

        CommandMenu("Controls") {
            Button(player.isPlaying ? "Pause" : "Play") { player.togglePlayPause() }
            Button("Next Track") { player.next() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Previous Track") { player.previous() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Divider()
            Button("Volume Up") { player.volume = min(1, player.volume + 0.1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Volume Down") { player.volume = max(0, player.volume - 0.1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Button(player.isMuted ? "Unmute" : "Mute") { player.toggleMute() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Divider()
            Toggle("Shuffle", isOn: Binding(get: { player.shuffleEnabled }, set: { _ in player.toggleShuffle() }))
                .keyboardShortcut("s", modifiers: [.command, .option])
            Button("Repeat: \(["Off", "All", "One"][player.repeatMode.rawValue])") { player.cycleRepeat() }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Divider()
            Button("Go to Current Album") {
                if let track = player.currentTrack, let album = library.index.album(for: track) {
                    router.showAlbum(album.id)
                }
            }
            .keyboardShortcut("l")
            .disabled(player.currentTrack == nil)
        }
    }
}
