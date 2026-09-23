import SwiftUI

struct LibraryBrowseView: View {
    let store: BrowseStore
    @Binding var selection: PlexItem?

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
                    onReachEnd: store.loadNextPage
                )
            }
        }
        .navigationTitle(store.section.title)
        .navigationSubtitle(store.totalSize.map(store.section.kind.itemCountLabel) ?? "")
        .onAppear(perform: store.loadIfNeeded)
    }
}
