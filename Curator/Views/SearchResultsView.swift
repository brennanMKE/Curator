import SwiftUI

struct SearchResultsView: View {
    @Binding var selection: PlexItem?

    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(SearchStore.self) private var search

    var body: some View {
        Group {
            if let results = search.results, results.query == search.trimmedQuery || !search.isSearching {
                if results.isEmpty {
                    emptyState(for: results.query)
                } else {
                    ItemCollectionView(
                        sections: sections(results),
                        selection: $selection,
                        subtitle: { item in
                            if results.otherMatches.contains(where: { $0.id == item.id }) {
                                return SearchResults.reasonLabel(for: item)
                            }
                            return item.displaySubtitle
                        }
                    )
                }
            } else if let error = search.error {
                ContentUnavailableView(error.localizedDescription, systemImage: "exclamationmark.triangle", description: Text(error.recoverySuggestion ?? ""))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Search")
        .navigationSubtitle(search.results.map { resultCount($0.titleMatches.count + $0.otherMatches.count) } ?? "")
        .task(id: "\(search.trimmedQuery)|\(library.revision)") {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let client = settings.plexClient else { return }
            await search.search(client: client, sections: library.sections)
        }
    }

    private func resultCount(_ count: Int) -> String {
        count == 1 ? "1 result" : "\(count) results"
    }

    private func sections(_ results: SearchResults) -> [ItemSection] {
        var sections: [ItemSection] = []
        if !results.titleMatches.isEmpty {
            sections.append(ItemSection(id: "titles", title: "Titles", items: results.titleMatches))
        }
        if !results.otherMatches.isEmpty {
            sections.append(ItemSection(id: "other", title: "Matched Cast, Crew & Similar Titles", items: results.otherMatches))
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
