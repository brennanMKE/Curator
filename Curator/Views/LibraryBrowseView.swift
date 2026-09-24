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
            } else if store.items.isEmpty, let genre = store.genre {
                ContentUnavailableView {
                    Label("No \(genre.title) Titles", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Nothing in \(store.section.title) is in this genre.")
                } actions: {
                    Button("Show All Genres") { store.setGenre(nil) }
                }
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
                // A new order or genre is a new list: start at the top rather than keeping the
                // old offset.
                .id("\(store.sort.storageValue) \(store.genre?.key ?? "")")
            }
        }
        .navigationTitle(store.section.title)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                GenreMenu(genres: store.genres, counts: store.genreCounts, genre: genreBinding)
            }
            ToolbarItem {
                SortMenu(sort: sortBinding)
            }
        }
        .onAppear {
            store.loadIfNeeded()
            store.loadGenresIfNeeded()
        }
    }

    /// "29 movies · Action" while a genre is chosen.
    private var subtitle: String {
        [store.totalSize.map(store.section.kind.itemCountLabel), store.genre?.title]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    private var genreBinding: Binding<PlexGenre?> {
        Binding { store.genre } set: { store.setGenre($0) }
    }

    private var sortBinding: Binding<LibrarySort> {
        Binding { model.librarySort } set: { model.librarySort = $0 }
    }
}
