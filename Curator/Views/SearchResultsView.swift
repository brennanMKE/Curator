import SwiftUI

struct SearchResultsView: View {
    @Binding var selection: PlexItem?

    @Environment(SearchStore.self) private var search
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let results = search.currentResults {
                if results.isEmpty {
                    emptyState(for: results.query)
                } else {
                    grid(for: results)
                }
            } else if let error = search.currentError {
                ContentUnavailableView(error.localizedDescription, systemImage: "exclamationmark.triangle", description: Text(error.recoverySuggestion ?? ""))
            } else if let previous = search.results, !previous.isEmpty {
                // Still searching: keep the last results visible, dimmed, rather than
                // presenting them as matches for the new text.
                grid(for: previous)
                    .opacity(0.4)
                    .allowsHitTesting(false)
                    .overlay { ProgressView() }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Search")
        .navigationSubtitle(search.currentResults.map { resultCount($0.titleMatches.count + $0.otherMatches.count) } ?? "Searching…")
        .toolbar {
            ToolbarItem {
                SortMenu(sort: Binding { model.librarySort } set: { model.librarySort = $0 })
            }
        }
    }

    private func grid(for results: SearchResults) -> some View {
        ItemCollectionView(
            sections: sections(results),
            selection: $selection,
            subtitle: { item in
                let field = model.librarySort.field
                if results.otherMatches.contains(where: { $0.id == item.id }) {
                    // Why it matched comes first; then the value it's sorted by.
                    return [SearchResults.reasonLabel(for: item), SortedValue.value(for: item, field)]
                        .compactMap(\.self).joined(separator: " · ")
                }
                return SortedValue.subtitle(for: item, sortedBy: field)
            }
        )
    }

    private func resultCount(_ count: Int) -> String {
        count == 1 ? "1 result" : "\(count) results"
    }

    private func sections(_ results: SearchResults) -> [ItemSection] {
        var sections: [ItemSection] = []
        // Sorted in the app: the results are merged from several requests.
        let sort = model.librarySort
        if !results.titleMatches.isEmpty {
            sections.append(ItemSection(id: "titles", title: "Titles", items: sort.sorted(results.titleMatches)))
        }
        if !results.otherMatches.isEmpty {
            sections.append(ItemSection(id: "other", title: "Matched Cast, Crew & Similar Titles", items: sort.sorted(results.otherMatches)))
        }
        return sections
    }

    private func emptyState(for query: String) -> some View {
        ContentUnavailableView {
            Label("No Results for “\(query)”", systemImage: "magnifyingglass")
        } description: {
            Text("""
                Plex matches whole words from their start — “lebowski” works, “ebowsk” doesn't — and spells titles its own way (“Bloodsport 2”, “&” not “and”). \
                A file on disk that Plex hasn't matched won't appear here.
                """)
        }
    }
}
