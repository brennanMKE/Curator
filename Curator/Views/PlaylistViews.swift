import SwiftUI

/// One playlist's titles, in order, as a grid or a list: drag one onto another to reorder,
/// Delete to remove.
struct PlaylistDetailView: View {
    let playlistID: String
    @Binding var selection: PlexItem?

    @Environment(PlaylistStore.self) private var playlists
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var isConfirmingDelete = false

    var body: some View {
        if let playlist = playlists.playlist(playlistID) {
            content(for: playlist)
                .navigationTitle(playlist.title)
                .navigationSubtitle(summary(of: playlist))
                .toolbar {
                    ToolbarItem {
                        Menu {
                            Button("Open in Plex", systemImage: "play.rectangle") { open(playlist) }
                            Button("Rename…", systemImage: "pencil") {
                                newName = playlist.title
                                isRenaming = true
                            }
                            Divider()
                            Button("Delete Playlist…", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                        } label: {
                            Label("Playlist", systemImage: "list.and.film")
                        }
                        // Without this, VoiceOver and UI tests see the symbol's name.
                        .accessibilityLabel("Playlist")
                        .accessibilityIdentifier("playlistMenu")
                        .help("Playlist actions")
                    }
                }
                .alert("Rename Playlist", isPresented: $isRenaming) {
                    TextField("Name", text: $newName)
                    Button("Rename") { playlists.rename(playlist, to: newName) }
                    Button("Cancel", role: .cancel) {}
                }
                .confirmationDialog("Delete “\(playlist.title)”?", isPresented: $isConfirmingDelete) {
                    Button("Delete Playlist", role: .destructive) { playlists.delete(playlist) }
                } message: {
                    Text("This deletes it from your Plex server, for every Plex app. The movies stay in your library.")
                }
                .onChange(of: playlistID, initial: true) { playlists.loadEntries(of: playlistID) }
        } else {
            ContentUnavailableView("Playlist Not Found", systemImage: "list.and.film", description: Text("It may have been deleted in another Plex app."))
        }
    }

    @ViewBuilder
    private func content(for playlist: PlexPlaylist) -> some View {
        if let entries = playlists.entries[playlist.id] {
            if entries.isEmpty {
                ContentUnavailableView("\(playlist.title) Is Empty", systemImage: "list.and.film",
                                       description: Text("Right-click a poster and choose Add to Playlist, or drag one onto this playlist in the sidebar."))
            } else {
                ItemCollectionView(
                    sections: [ItemSection(id: playlist.id, title: nil, items: entries)],
                    selection: $selection,
                    subtitle: { entry in
                        [entry.displaySubtitle, entry.duration.map { Format.runtime(milliseconds: $0) }]
                            .compactMap(\.self)
                            .joined(separator: " · ")
                    },
                    numbered: true,
                    editing: CollectionEditing(
                        remove: { playlists.remove($0, from: playlist) },
                        move: { dragged, target in move(dragged, onto: target, in: playlist, entries: entries) }
                    ),
                    cellIdentifier: "playlistEntry"
                )
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Dropping an entry on another takes the target's place: after it when dragged down, before
    /// it when dragged up.
    private func move(_ dragged: PlaylistCandidate, onto target: PlexItem, in playlist: PlexPlaylist, entries: [PlexItem]) -> Bool {
        guard let draggedID = dragged.playlistItemID,
              let from = entries.firstIndex(where: { $0.playlistItemID == draggedID }),
              let to = entries.firstIndex(where: { $0.entryID == target.entryID }),
              from != to
        else { return false }
        playlists.move(in: playlist, from: IndexSet(integer: from), to: to > from ? to + 1 : to)
        return true
    }

    private func summary(of playlist: PlexPlaylist) -> String {
        let count = playlist.leafCount == 1 ? "1 title" : "\(playlist.leafCount) titles"
        return [count, playlist.duration.map { Format.runtime(milliseconds: $0) }].compactMap(\.self).joined(separator: " · ")
    }

    private func open(_ playlist: PlexPlaylist) {
        guard let server = model.library.server,
              let url = model.settings.plexClient?.webURL(forPlaylist: playlist.id, machineIdentifier: server.machineIdentifier)
        else { return }
        openURL(url)
    }
}

/// Every playlist, A to Z; shown when there are more than fit in the sidebar.
struct AllPlaylistsView: View {
    let open: (String) -> Void

    @Environment(PlaylistStore.self) private var playlists

    var body: some View {
        List(playlists.alphabetical) { playlist in
            Button {
                open(playlist.id)
            } label: {
                HStack {
                    Label(playlist.title, systemImage: "list.and.film")
                    Spacer()
                    Text(playlist.leafCount == 1 ? "1 title" : "\(playlist.leafCount) titles")
                        .foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .dropDestination(for: PlaylistCandidate.self) { candidates, _ in
                candidates.forEach { playlists.add($0, to: playlist) }
                return !candidates.isEmpty
            }
        }
        .navigationTitle("Playlists")
        .navigationSubtitle(playlists.playlists.count == 1 ? "1 playlist" : "\(playlists.playlists.count) playlists")
    }
}

/// Names a new playlist that starts with the title it was opened for.
struct NewPlaylistSheet: View {
    let candidate: PlaylistCandidate

    @Environment(PlaylistStore.self) private var playlists
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(candidate: PlaylistCandidate) {
        self.candidate = candidate
        _name = State(initialValue: candidate.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Playlist").font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("newPlaylistName")
            Text("Starts with \(candidate.title). The playlist is saved on your Plex server, so it plays in every Plex app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    playlists.create(named: name, with: candidate)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

/// The outcome of a playlist change, at the bottom of the window.
struct PlaylistBanner: View {
    let event: PlaylistEvent

    @Environment(PlaylistStore.self) private var playlists

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(event.message)
                .lineLimit(2)
                .accessibilityIdentifier("playlistBanner")
            if event.undo != nil {
                Button("Undo") { playlists.undo() }
            }
            Button("Dismiss", systemImage: "xmark") { playlists.dismissEvent() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: .capsule)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .padding(.bottom, 16)
    }

    private var symbol: String {
        switch event.kind {
        case .success: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .failure: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch event.kind {
        case .success: .green
        case .info: .secondary
        case .failure: .orange
        }
    }
}

extension PlexItem {
    /// Unique within a playlist even if a title appears twice; the rating key elsewhere.
    var entryID: String { playlistItemID ?? ratingKey }
}
