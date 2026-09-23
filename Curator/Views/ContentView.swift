import SwiftUI

enum SidebarItem: Hashable {
    case recentlyAdded
    case library(String)
}

struct FocusSearchAction {
    let perform: () -> Void
    func callAsFunction() { perform() }
}

extension FocusedValues {
    @Entry var focusSearch: FocusSearchAction?
}

struct ContentView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(TMDBStore.self) private var tmdb
    @Environment(SearchStore.self) private var search
    @State private var sidebarSelection: SidebarItem? = .recentlyAdded
    @State private var selectedItem: PlexItem?
    @State private var showInspector = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var search = search

        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            MainContent(sidebarSelection: sidebarSelection, selection: $selectedItem)
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
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await library.refresh(using: settings) }
                }
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
        // Reconnect whenever the address or token changes, after typing settles.
        .task(id: settings.plexConnectionKey) {
            if library.lastRefreshed != nil || library.status != .notConfigured {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
            }
            await library.refresh(using: settings)
        }
        // Check the TMDB key whenever it changes; artwork falls back to Plex until it's valid.
        .task(id: settings.tmdbKey.trimmed) {
            if tmdb.status != .off {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
            }
            await tmdb.validate(using: settings)
        }
    }
}

/// Everything needs a working Plex connection; until then, show how to get one.
private struct MainContent: View {
    let sidebarSelection: SidebarItem?
    @Binding var selection: PlexItem?

    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(SearchStore.self) private var search

    var body: some View {
        switch library.status {
        case .notConfigured:
            ContentUnavailableView {
                Label("Connect to Plex", systemImage: "server.rack")
            } description: {
                Text("Add your Plex server address and token in Settings.")
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
                    Button("Try Again") {
                        Task { await library.refresh(using: settings) }
                    }
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
                        LibraryBrowseView(section: item.section, selection: $selection)
                            .id(key)
                    } else {
                        ContentUnavailableView("Library Not Found", systemImage: "questionmark.folder")
                    }
                }
            }
        }
    }
}
