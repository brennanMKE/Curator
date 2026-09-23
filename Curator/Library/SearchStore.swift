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
    static let debounce: Duration = .milliseconds(300)

    /// Bound to the search field. Changing it schedules a search; the view never does.
    var query = "" {
        didSet {
            guard query.trimmed != oldValue.trimmed else { return }
            schedule(after: Self.debounce)
        }
    }

    /// The latest completed search; its `query` may lag behind what's being typed.
    private(set) var results: SearchResults?
    /// True from the first keystroke until results for the current text arrive.
    private(set) var isSearching = false
    private(set) var error: PlexError?
    /// The query `error` belongs to.
    private(set) var errorQuery: String?

    @ObservationIgnored var context: () -> PlexContext? = { nil }
    @ObservationIgnored private var task: Task<Void, Never>?
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

    /// Searches again immediately, e.g. after reconnecting.
    func rerun() {
        schedule(after: .zero)
    }

    private func schedule(after delay: Duration) {
        task?.cancel()
        generation += 1
        let current = generation
        let text = trimmedQuery

        guard !text.isEmpty else {
            results = nil
            error = nil
            errorQuery = nil
            isSearching = false
            return
        }
        isSearching = true

        task = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            await self?.perform(text, generation: current)
        }
    }

    private func perform(_ text: String, generation current: Int) async {
        guard let context = context() else {
            // Not connected; the next connect calls rerun().
            if current == generation { isSearching = false }
            return
        }
        Log.plex.debug("Search \"\(text, privacy: .public)\" started")

        let result: Result<SearchResults, PlexError>
        do {
            async let hubs = try? context.client.hubSearch(text)
            let titles = try await withThrowingTaskGroup(of: (Int, [PlexItem]).self) { group in
                for (index, section) in context.sections.enumerated() {
                    group.addTask { (index, try await context.client.search(title: text, in: section)) }
                }
                var found: [(Int, [PlexItem])] = []
                for try await result in group { found.append(result) }
                return found.sorted { $0.0 < $1.0 }.map(\.1)
            }
            result = .success(SearchResults.merge(query: text, titleMatches: titles, hubs: await hubs ?? []))
        } catch is CancellationError {
            result = .failure(.cancelled)
        } catch {
            result = .failure(error as? PlexError ?? .badResponse)
        }

        // Only the newest search may touch state.
        guard current == generation else {
            Log.plex.debug("Search \"\(text, privacy: .public)\" superseded")
            return
        }
        isSearching = false
        switch result {
        case .success(let merged):
            results = merged
            error = nil
            errorQuery = nil
            Log.plex.info("Search \"\(text, privacy: .public)\": \(merged.titleMatches.count) titles, \(merged.otherMatches.count) other")
        case .failure(.cancelled):
            break
        case .failure(let failure):
            error = failure
            errorQuery = text
            Log.plex.error("Search \"\(text, privacy: .public)\" failed: \(failure.localizedDescription, privacy: .public)")
        }
    }
}
