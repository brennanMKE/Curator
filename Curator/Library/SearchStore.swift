import Foundation
import Observation
import os

nonisolated struct SearchResults: Sendable, Equatable {
    let query: String
    /// Every title that word-prefix matches, from the section filters. Complete.
    let titleMatches: [PlexItem]
    /// Hub-only hits: cast, crew and forgiving-spelling matches the title filter can't find.
    let otherMatches: [PlexItem]

    var isEmpty: Bool { titleMatches.isEmpty && otherMatches.isEmpty }

    static let hubTypes: Set<String> = ["movie", "show", "episode"]

    static func merge(query: String, titleMatches: [[PlexItem]], hubs: [PlexHub]) -> SearchResults {
        var seen = Set<String>()
        let titles = titleMatches.joined().filter { seen.insert($0.id).inserted }
        let others = hubs
            .filter { hubTypes.contains($0.type) }
            .flatMap(\.items)
            .filter { seen.insert($0.id).inserted }
        return SearchResults(query: query, titleMatches: titles, otherMatches: others)
    }

    /// "Director: Joel Coen" for hub matches; "Similar title" when Plex gives no reason.
    static func reasonLabel(for item: PlexItem) -> String {
        guard let reason = item.reason else { return "Similar title" }
        let role = switch reason {
        case "actor": "Cast"
        default: reason.capitalized
        }
        return item.reasonTitle.map { "\(role): \($0)" } ?? role
    }
}

@Observable
final class SearchStore {
    var query = ""
    /// The latest completed search; its `query` may lag behind what's being typed.
    private(set) var results: SearchResults?
    private(set) var isSearching = false
    private(set) var error: PlexError?
    /// The query `error` belongs to.
    private(set) var errorQuery: String?

    /// Each search supersedes the ones before it, so a cancelled or slow search can't
    /// clear `isSearching` early or overwrite newer results.
    @ObservationIgnored private var generation = 0

    var trimmedQuery: String { query.trimmed }

    /// Results for exactly what's in the search field, if they've arrived.
    var currentResults: SearchResults? {
        results.flatMap { $0.query == trimmedQuery ? $0 : nil }
    }

    var currentError: PlexError? {
        errorQuery == trimmedQuery ? error : nil
    }

    func search(client: PlexClient, sections: [PlexSection]) async {
        generation += 1
        let current = generation
        let text = trimmedQuery
        guard !text.isEmpty else {
            results = nil
            error = nil
            isSearching = false
            return
        }

        isSearching = true
        defer { if current == generation { isSearching = false } }

        do {
            async let hubs = try? client.hubSearch(text)
            let titles = try await withThrowingTaskGroup(of: (Int, [PlexItem]).self) { group in
                for (index, section) in sections.enumerated() {
                    group.addTask { (index, try await client.search(title: text, in: section)) }
                }
                var found: [(Int, [PlexItem])] = []
                for try await result in group { found.append(result) }
                return found.sorted { $0.0 < $1.0 }.map(\.1)
            }
            let merged = SearchResults.merge(query: text, titleMatches: titles, hubs: await hubs ?? [])
            guard current == generation else { return }
            results = merged
            error = nil
            errorQuery = nil
            Log.plex.info("Search \"\(text, privacy: .public)\": \(merged.titleMatches.count) titles, \(merged.otherMatches.count) other")
        } catch PlexError.cancelled {
            Log.plex.debug("Search \"\(text, privacy: .public)\" cancelled")
        } catch is CancellationError {
            Log.plex.debug("Search \"\(text, privacy: .public)\" cancelled")
        } catch {
            guard current == generation else { return }
            self.error = error as? PlexError ?? .badResponse
            errorQuery = text
            Log.plex.error("Search \"\(text, privacy: .public)\" failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
