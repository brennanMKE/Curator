import SwiftUI

enum SidebarItem: Hashable {
    case recentlyAdded
    case library(String)
}

struct ContentView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @State private var selection: SidebarItem? = .recentlyAdded

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            DetailView(selection: selection)
        }
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await library.refresh(using: settings) }
                }
                .help("Refresh (⌘R)")
                .disabled(!settings.isPlexConfigured || library.status == .connecting)
            }
        }
        // Reconnect whenever the address or token changes, after typing settles.
        .task(id: settings.plexConnectionKey) {
            if library.lastRefreshed != nil || library.status != .notConfigured {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
            }
            await library.refresh(using: settings)
        }
    }
}

private struct DetailView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    let selection: SidebarItem?

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
            switch selection {
            case .recentlyAdded, nil:
                ContentUnavailableView(
                    "Recently Added",
                    systemImage: "clock",
                    description: Text("The newest imports across your libraries will appear here.")
                )
            case .library(let key):
                if let item = library.libraries.first(where: { $0.id == key }) {
                    ContentUnavailableView(
                        item.section.title,
                        systemImage: item.section.kind.systemImage,
                        description: Text(item.itemCount.map(item.section.kind.itemCountLabel) ?? "")
                    )
                } else {
                    ContentUnavailableView("Library not found", systemImage: "questionmark.folder")
                }
            }
        }
    }
}
