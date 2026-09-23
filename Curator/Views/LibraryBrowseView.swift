import SwiftUI

struct LibraryBrowseView: View {
    let store: BrowseStore
    @Binding var selection: PlexItem?

    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if !store.hasLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.items.isEmpty, let error = store.error {
                ContentUnavailableView(error.localizedDescription, systemImage: "exclamationmark.triangle", description: Text(error.recoverySuggestion ?? ""))
            } else if store.items.isEmpty {
                ContentUnavailableView(
                    "\(store.section.title) Is Empty",
                    systemImage: store.section.kind.systemImage,
                    description: Text("Nothing has been added to this library yet.")
                )
            } else {
                ItemCollectionView(
                    sections: [ItemSection(id: store.section.id, title: nil, items: store.items)],
                    selection: $selection,
                    subtitle: { SortedValue.subtitle(for: $0, sortedBy: store.sort.field) },
                    onReachEnd: store.loadNextPage
                )
                // A new order is a new list: start at the top rather than keeping the old offset.
                .id(store.sort)
            }
        }
        .navigationTitle(store.section.title)
        .navigationSubtitle(store.totalSize.map(store.section.kind.itemCountLabel) ?? "")
        .toolbar {
            ToolbarItem {
                SortMenu(sort: sortBinding)
            }
        }
        .onAppear(perform: store.loadIfNeeded)
    }

    private var sortBinding: Binding<LibrarySort> {
        Binding { model.librarySort } set: { model.librarySort = $0 }
    }
}
