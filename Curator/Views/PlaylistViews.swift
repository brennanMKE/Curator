import SwiftUI

/// One playlist's titles, in order: drag to reorder, Delete to remove.
struct PlaylistDetailView: View {
    let playlistID: String
    @Binding var selection: PlexItem?

    @Environment(PlaylistStore.self) private var playlists
    @Environment(AppModel.self) private var model
    @Environment(\.itemActions) private var actions
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
                List(selection: selectedEntry(in: entries)) {
                    ForEach(Array(entries.enumerated()), id: \.element.entryID) { index, entry in
                        PlaylistEntryRow(index: index + 1, entry: entry)
                            .tag(entry.entryID)
                            .accessibilityIdentifier("playlistEntry")
                    }
                    .onMove { source, destination in
                        playlists.move(in: playlist, from: source, to: destination)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .contextMenu(forSelectionType: String.self) { ids in
                    if let entry = ids.first.flatMap({ id in entries.first { $0.entryID == id } }) {
                        Button("Remove from Playlist") { playlists.remove(entry, from: playlist) }
                        Divider()
                        ItemContextMenu(item: entry)
                    }
                } primaryAction: { ids in
                    if let entry = ids.first.flatMap({ id in entries.first { $0.entryID == id } }) { actions.open(entry) }
                }
                .onDeleteCommand {
                    if let entry = selection, entries.contains(where: { $0.entryID == entry.entryID }) {
                        playlists.remove(entry, from: playlist)
                    }
                }
                .onKeyPress(.space) {
                    guard let selection else { return .ignored }
                    actions.preview(selection)
                    return .handled
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func selectedEntry(in entries: [PlexItem]) -> Binding<String?> {
        Binding {
            selection?.entryID
        } set: { id in
            selection = id.flatMap { id in entries.first { $0.entryID == id } }
        }
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

private struct PlaylistEntryRow: View {
    let index: Int
    let entry: PlexItem

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            Color.clear
                .frame(width: 28, height: 42)
                .overlay { ArtworkView(item: entry, kind: .poster) }
                .clipShape(.rect(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayTitle).lineLimit(1)
                if let subtitle = entry.displaySubtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let duration = entry.duration {
                Text(Format.runtime(milliseconds: duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
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
