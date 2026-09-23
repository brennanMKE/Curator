import Foundation
import Observation

/// The newest items across all libraries, polled every minute by `AppModel`.
@Observable
final class RecentStore {
    static let pageSize = 60

    private(set) var items: [PlexItem] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var hasMore = false
    private(set) var error: PlexError?
    /// Items that appeared during this session's polling; drives the "just added" banner.
    private(set) var arrivals: [PlexItem] = []

    /// Imports this recent get a NEW badge.
    nonisolated static let newWindow: TimeInterval = 3 * 60 * 60

    @ObservationIgnored var context: () -> PlexContext? = { nil }
    @ObservationIgnored private var loadMoreTask: Task<Void, Never>?
    @ObservationIgnored private var limit = pageSize
    @ObservationIgnored private var generation = 0

    init() {
        // Earlier builds tracked a "seen" date; badges are now purely time-based.
        UserDefaults.standard.removeObject(forKey: "recentSeenBaseline")
        UserDefaults.standard.removeObject(forKey: "recentNextBaseline")
    }

    nonisolated static func isNew(_ item: PlexItem, now: Date = .now) -> Bool {
        guard let addedAt = item.addedAt else { return false }
        return now.timeIntervalSince(addedAt) < newWindow
    }

    func newCount(now: Date = .now) -> Int {
        items.count { Self.isNew($0, now: now) }
    }

    /// Reloads the newest `limit` items from every library. `reset` starts over from one page
    /// (after connecting to a different server); otherwise it refreshes what's shown and
    /// records arrivals. Called by `AppModel`'s polling, not by views.
    func load(reset: Bool = false) async {
        guard let context = context() else { return }
        let client = context.client
        let sections = context.sections
        generation += 1
        let current = generation
        if reset {
            limit = Self.pageSize
            items = []
            arrivals = []
            hasLoaded = false
        }

        isLoading = true
        defer { if current == generation { isLoading = false } }

        let page = PlexClient.Page(start: 0, size: limit)
        var fetched: [PlexItem] = []
        var more = false
        var failure: PlexError?

        await withTaskGroup(of: Result<PlexItemList, PlexError>.self) { group in
            for section in sections {
                group.addTask {
                    do {
                        return .success(try await client.items(in: section, sort: .newest, episodes: section.kind == .show, page: page))
                    } catch {
                        return .failure(error as? PlexError ?? .badResponse)
                    }
                }
            }
            for await result in group {
                switch result {
                case .success(let list):
                    fetched += list.items
                    if (list.totalSize ?? 0) > list.items.count { more = true }
                case .failure(let error):
                    failure = error
                }
            }
        }

        guard current == generation, failure != .cancelled else { return }

        fetched.sort { ($0.addedAt ?? .distantPast, $0.title) > ($1.addedAt ?? .distantPast, $1.title) }
        if hasLoaded {
            let known = Set(items.map(\.id))
            let newest = items.first?.addedAt ?? .distantPast
            let arrived = fetched.filter { !known.contains($0.id) && ($0.addedAt ?? .distantPast) > newest }
            arrivals = arrived + arrivals.filter { !arrived.map(\.id).contains($0.id) }
        }

        items = fetched
        hasMore = more
        error = failure
        hasLoaded = true
    }

    /// Intent from the view when the last item scrolls into sight.
    func loadMore() {
        guard hasMore, !isLoading, loadMoreTask == nil else { return }
        limit += Self.pageSize
        loadMoreTask = Task { [weak self] in
            await self?.load()
            self?.loadMoreTask = nil
        }
    }

    func dismissArrivals() {
        arrivals = []
    }
}
