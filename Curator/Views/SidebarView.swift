import SwiftUI

struct SidebarView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaylistStore.self) private var playlists
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Label("Recently Added", systemImage: "clock")
                .tag(SidebarItem.recentlyAdded)

            if !library.libraries.isEmpty {
                Section("Libraries") {
                    ForEach(library.libraries) { item in
                        Label(item.section.title, systemImage: item.section.kind.systemImage)
                            .badge(item.itemCount ?? 0)
                            .tag(SidebarItem.library(item.id))
                    }
                }
            }

            if library.status == .connected {
                Section("Playlists") {
                    // The most recently changed; each accepts dropped titles.
                    ForEach(playlists.byRecency.prefix(PlaylistStore.sidebarCount)) { playlist in
                        PlaylistSidebarRow(playlist: playlist)
                            .tag(SidebarItem.playlist(playlist.id))
                    }
                    if playlists.playlists.count > PlaylistStore.sidebarCount {
                        Label("All Playlists", systemImage: "square.stack")
                            .tag(SidebarItem.allPlaylists)
                    }
                    NewPlaylistSidebarRow()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            ConnectionStatusView()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }
}

/// A playlist in the sidebar. Dropping a title on it adds the title.
private struct PlaylistSidebarRow: View {
    let playlist: PlexPlaylist

    @Environment(PlaylistStore.self) private var playlists
    @State private var isTargeted = false

    var body: some View {
        Label(playlist.title, systemImage: "list.and.film")
            .badge(playlist.leafCount)
            .accessibilityIdentifier("sidebarPlaylist")
            .dropDestination(for: PlaylistCandidate.self) { candidates, _ in
                candidates.forEach { playlists.add($0, to: playlist) }
                return !candidates.isEmpty
            } isTargeted: { isTargeted = $0 }
            .listRowBackground(isTargeted ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.3)) : nil)
    }
}

/// Starts a playlist with whatever is dropped on it. Plex won't create an empty playlist, so a
/// click explains how instead.
private struct NewPlaylistSidebarRow: View {
    @Environment(\.itemActions) private var actions
    @State private var isTargeted = false
    @State private var showsHint = false

    var body: some View {
        Button {
            showsHint = true
        } label: {
            Label("New Playlist", systemImage: "plus")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("newPlaylistDrop")
        .dropDestination(for: PlaylistCandidate.self) { candidates, _ in
            guard let first = candidates.first else { return false }
            actions.newPlaylist(first)
            return true
        } isTargeted: { isTargeted = $0 }
        .listRowBackground(isTargeted ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.3)) : nil)
        .popover(isPresented: $showsHint, arrowEdge: .trailing) {
            Text("A playlist starts with a title. Drag a poster here, or right-click one and choose Add to Playlist › New Playlist….")
                .font(.callout)
                .frame(width: 260)
                .fixedSize(horizontal: false, vertical: true)
                .padding()
        }
    }
}

/// A one-line indicator of the Plex connection, shown under the sidebar.
struct ConnectionStatusView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        HStack(spacing: 6) {
            switch library.status {
            case .notConfigured:
                indicator(.secondary)
                Text("Not connected")
            case .connecting:
                ProgressView().controlSize(.mini)
                Text("Connecting…")
            case .connected:
                indicator(.green)
                Text(library.server?.friendlyName ?? "Connected")
                    .lineLimit(1)
                    .truncationMode(.middle)
            case .failed:
                indicator(.red)
                Text("Connection failed")
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .help(helpText)
    }

    private func indicator(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 7, height: 7)
    }

    private var helpText: String {
        switch library.status {
        case .connected:
            guard let server = library.server else { return "" }
            return "Plex Media Server \(server.shortVersion)"
        case .failed(let error):
            return error.localizedDescription
        default:
            return ""
        }
    }
}
