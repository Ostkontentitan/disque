import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        Form {
            Section {
                if library.folders.isEmpty {
                    Text("No folders yet. Add a folder that contains your MP3 files.")
                        .foregroundStyle(.secondary)
                }
                ForEach(library.folders, id: \.self) { folder in
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text((folder as NSString).lastPathComponent)
                            Text((folder as NSString).abbreviatingWithTildeInPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button {
                            NSWorkspace.shared.open(URL(fileURLWithPath: folder))
                        } label: {
                            Image(systemName: "arrow.up.forward.app")
                        }
                        .buttonStyle(.borderless)
                        .help("Open in Finder")
                        Button {
                            library.removeFolder(folder)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red.opacity(0.85))
                        }
                        .buttonStyle(.borderless)
                        .help("Remove from Library (files are not deleted)")
                    }
                }
                HStack {
                    Button("Add Folder…") { library.presentAddFolderPanel() }
                    Spacer()
                }
            } header: {
                Text("Music Folders")
            } footer: {
                Text("Folders are watched for changes. Removing a folder only removes it from Disque — your files stay where they are.")
                    .foregroundStyle(.secondary)
            }

            Section("Library") {
                LabeledContent("Tracks", value: library.index.tracks.count.formatted())
                LabeledContent("Albums", value: library.index.albums.count.formatted())
                LabeledContent("Artists", value: library.index.artists.count.formatted())
                LabeledContent("Total playing time", value: Formatters.longDuration(library.index.totalDuration))
                HStack {
                    Button("Rescan Now") { library.rescan() }
                        .disabled(library.isScanning)
                    Button("Rebuild From Scratch") {
                        ArtworkLoader.shared.clearFolderCache()
                        library.rebuildFromScratch()
                    }
                    .disabled(library.isScanning)
                    Spacer()
                    if library.isScanning {
                        ProgressView().controlSize(.small)
                        Text("Scanning…").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 520)
        .preferredColorScheme(.dark)
    }
}
