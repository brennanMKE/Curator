import SwiftUI

enum SidebarItem: Hashable {
    case recentlyAdded
    case library(String)
    case playlist(String)
    case allPlaylists
}

struct FocusSearchAction {
    let perform: () -> Void
    func callAsFunction() { perform() }
}

extension FocusedValues {
    @Entry var focusSearch: FocusSearchAction?
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(SearchStore.self) private var search
    @Environment(AppNavigation.self) private var navigation
    @Environment(PlaylistStore.self) private var playlists
    @State private var newPlaylistCandidate: PlaylistCandidate?
    @State private var sidebarSelection: SidebarItem? = .recentlyAdded
    @State private var selectedItem: PlexItem?
    @State private var showInspector = false
    @State private var previewItem: PlexItem?
    @AppStorage(ViewMode.storageKey) private var viewMode = ViewMode.grid
    @Environment(\.openURL) private var openURL
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var search = search

        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            MainContent(sidebarSelection: $sidebarSelection, selection: $selectedItem)
                .inspector(isPresented: $showInspector) {
                    Group {
                        if let selectedItem {
                            ItemDetailView(item: selectedItem)
                        } else {
                            ContentUnavailableView("No Selection", systemImage: "sidebar.trailing", description: Text("Select a title to see its details."))
                        }
                    }
                    .inspectorColumnWidth(min: 280, ideal: 340, max: 480)
                }
        }
        .searchable(text: $search.query, placement: .toolbar, prompt: "Titles, actors, directors")
        .searchFocused($searchFocused)
        .focusedSceneValue(\.focusSearch, FocusSearchAction { searchFocused = true })
        .environment(\.itemActions, ItemActions(
            preview: { previewItem = $0 },
            open: openInPlex,
            newPlaylist: { newPlaylistCandidate = $0 }
        ))
        .sheet(item: $newPlaylistCandidate) { candidate in
            NewPlaylistSheet(candidate: candidate)
        }
        .overlay(alignment: .bottom) {
            // Scoped animation: only the banner moves.
            VStack {
                if let event = playlists.event {
                    PlaylistBanner(event: event)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.default, value: playlists.event?.id)
        }
        // A playlist deleted here or elsewhere can't stay selected.
        .onChange(of: playlists.playlists.map(\.id)) {
            if case .playlist(let id) = sidebarSelection, playlists.hasLoaded, playlists.playlist(id) == nil {
                sidebarSelection = .recentlyAdded
            }
        }
        .sheet(item: $previewItem) { item in
            ItemPreview(item: item)
                .environment(\.itemActions, ItemActions(open: openInPlex))
        }
        .toolbar {
            ToolbarItem {
                Picker("View", selection: $viewMode) {
                    Label("Grid", systemImage: "square.grid.2x2").tag(ViewMode.grid)
                    Label("List", systemImage: "list.bullet").tag(ViewMode.list)
                }
                .pickerStyle(.segmented)
                .help("Show as grid or list")
            }
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") { model.refresh() }
                .help("Refresh (⌘R)")
                .disabled(!settings.isPlexConfigured || library.status == .connecting)
            }
            ToolbarItem {
                Button("Details", systemImage: "sidebar.trailing") {
                    showInspector.toggle()
                }
                .help("Show or hide details")
            }
        }
        .onChange(of: selectedItem) {
            if selectedItem != nil { showInspector = true }
        }
        .onChange(of: sidebarSelection) {
            search.query = ""
            selectedItem = nil
        }
        .onChange(of: navigation.pendingItem, initial: true) {
            guard let item = navigation.pendingItem else { return }
            navigation.pendingItem = nil
            search.query = ""
            selectedItem = item
            showInspector = true
        }
    }
}

extension ContentView {
    private func openInPlex(_ item: PlexItem) {
        guard let server = library.server,
              let url = settings.plexClient?.webURL(for: item, machineIdentifier: server.machineIdentifier)
        else { return }
        openURL(url)
    }
}

/// Everything needs a working Plex connection; until then, show how to get one.
private struct MainContent: View {
    @Binding var sidebarSelection: SidebarItem?
    @Binding var selection: PlexItem?

    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(SearchStore.self) private var search

    var body: some View {
        switch library.status {
        case .notConfigured:
            ContentUnavailableView {
                Label("Connect to Plex", systemImage: "server.rack")
            } description: {
                Text("Curator needs your Plex server's address and your Plex token. Settings walks you through finding both.")
            } actions: {
                SettingsLink { Text("Open Settings…") }
                    .buttonStyle(.borderedProminent)
            }
        case .connecting where library.libraries.isEmpty:
            ProgressView("Connecting to \(settings.serverURL?.host() ?? "Plex")…")
        case .failed(let error):
            ContentUnavailableView {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.recoverySuggestion ?? "")
            } actions: {
                HStack {
                    Button("Try Again") { model.refresh() }
                    SettingsLink { Text("Open Settings…") }
                }
            }
        case .connected, .connecting:
            if !search.trimmedQuery.isEmpty {
                SearchResultsView(selection: $selection)
            } else {
                switch sidebarSelection {
                case .recentlyAdded, nil:
                    RecentlyAddedView(selection: $selection)
                case .library(let key):
                    if let item = library.libraries.first(where: { $0.id == key }) {
                        LibraryBrowseView(store: model.browseStore(for: item.section), selection: $selection)
                            .id(key)
                    } else {
                        ContentUnavailableView("Library Not Found", systemImage: "questionmark.folder")
                    }
                case .playlist(let id):
                    PlaylistDetailView(playlistID: id, selection: $selection)
                        .id(id)
                case .allPlaylists:
                    AllPlaylistsView { sidebarSelection = .playlist($0) }
                }
            }
        }
    }
}
