import Foundation
import Observation

/// The newest items across all libraries, polled while Recently Added is on screen.
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
    /// Items added after this moment get a "New" badge.
    private(set) var seenBaseline: Date?

    @ObservationIgnored private var limit = pageSize
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var generation = 0
    private static let baselineKey = "recentSeenBaseline"
    private static let nextBaselineKey = "recentNextBaseline"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // What the last session showed becomes this session's "seen" line, so anything
        // imported while the app was closed is marked New.
        let next = defaults.double(forKey: Self.nextBaselineKey)
        if next > 0 {
            defaults.set(next, forKey: Self.baselineKey)
            defaults.removeObject(forKey: Self.nextBaselineKey)
        }
        let stored = defaults.double(forKey: Self.baselineKey)
        seenBaseline = stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    func isNew(_ item: PlexItem) -> Bool {
        guard let seenBaseline, let addedAt = item.addedAt else { return false }
        return addedAt > seenBaseline
    }

    var newCount: Int { items.count(where: isNew) }

    /// Reloads the newest `limit` items from every library. `reset` starts over from one page
    /// (after reconnecting); otherwise it refreshes what's shown and records arrivals.
    func load(client: PlexClient, sections: [PlexSection], reset: Bool = false) async {
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

        if seenBaseline == nil {
            // First run: nothing counts as new until something arrives.
            markAllSeen()
        } else if let newest = items.first?.addedAt {
            defaults.set(newest.timeIntervalSince1970, forKey: Self.nextBaselineKey)
        }
    }

    func loadMore(client: PlexClient, sections: [PlexSection]) async {
        guard hasMore, !isLoading else { return }
        limit += Self.pageSize
        await load(client: client, sections: sections)
    }

    func markAllSeen() {
        let newest = items.first?.addedAt ?? .now
        seenBaseline = newest
        arrivals = []
        defaults.set(newest.timeIntervalSince1970, forKey: Self.baselineKey)
        defaults.removeObject(forKey: Self.nextBaselineKey)
    }

    func dismissArrivals() {
        arrivals = []
    }

}
