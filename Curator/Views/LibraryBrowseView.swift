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
                    subtitle: { subtitle(for: $0, sortedBy: store.sort.field) },
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

    /// Each poster's second line shows the value it's sorted by.
    private func subtitle(for item: PlexItem, sortedBy field: LibrarySort.Field) -> String? {
        let year = item.year.map(String.init)
        switch field {
        case .title:
            return item.displaySubtitle
        case .releaseDate:
            return item.releaseDate.map(Format.releaseDate) ?? year
        case .dateAdded:
            return [year, item.addedAt.map { "added " + Format.relative($0) }].compactMap(\.self).joined(separator: " · ")
        case .rating:
            return [item.audienceRating.map { String(format: "★ %.1f", $0) }, year].compactMap(\.self).joined(separator: " · ")
        }
    }
}

/// The toolbar's Sort menu: which field, then the order in words that fit it.
private struct SortMenu: View {
    @Binding var sort: LibrarySort

    var body: some View {
        Menu {
            Picker("Sort By", selection: fieldBinding) {
                ForEach(LibrarySort.Field.allCases, id: \.self) { field in
                    Text(field.label).tag(field)
                }
            }
            .pickerStyle(.inline)

            Picker("Order", selection: $sort.ascending) {
                Text(sort.field.orderLabels.ascending).tag(true)
                Text(sort.field.orderLabels.descending).tag(false)
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sorted by \(sort.field.label.lowercased()), \(orderLabel.lowercased())")
    }

    private var orderLabel: String {
        sort.ascending ? sort.field.orderLabels.ascending : sort.field.orderLabels.descending
    }

    /// Picking a field starts with its natural order (A to Z, newest or highest first).
    private var fieldBinding: Binding<LibrarySort.Field> {
        Binding { sort.field } set: { sort = sort.with(field: $0) }
    }
}
