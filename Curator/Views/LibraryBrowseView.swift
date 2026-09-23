import SwiftUI

struct LibraryBrowseView: View {
    @Binding var selection: PlexItem?
    @State private var store: BrowseStore

    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library

    init(section: PlexSection, selection: Binding<PlexItem?>) {
        _selection = selection
        _store = State(initialValue: BrowseStore(section: section))
    }

    var body: some View {
        Group {
            if store.items.isEmpty {
                if store.isLoading || store.totalSize == nil && store.error == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = store.error {
                    ContentUnavailableView(error.localizedDescription, systemImage: "exclamationmark.triangle", description: Text(error.recoverySuggestion ?? ""))
                } else {
                    ContentUnavailableView(
                        "\(store.section.title) Is Empty",
                        systemImage: store.section.kind.systemImage,
                        description: Text("Nothing has been added to this library yet.")
                    )
                }
            } else {
                PosterGrid(
                    sections: [PosterSection(id: store.section.id, title: nil, items: store.items)],
                    selection: $selection,
                    onReachEnd: {
                        guard let client = settings.plexClient else { return }
                        Task { await store.loadNextPage(client: client) }
                    }
                )
            }
        }
        .navigationTitle(store.section.title)
        .navigationSubtitle(store.totalSize.map(store.section.kind.itemCountLabel) ?? "")
        .task(id: library.revision) {
            guard let client = settings.plexClient else { return }
            await store.reload(client: client)
        }
    }
}
