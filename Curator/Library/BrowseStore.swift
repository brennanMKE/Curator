import Foundation
import Observation

/// One library's items in title order, loaded a page at a time.
@Observable
final class BrowseStore {
    static let pageSize = 120

    let section: PlexSection
    private(set) var items: [PlexItem] = []
    private(set) var totalSize: Int?
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var error: PlexError?

    /// Each reload supersedes any request still in flight, so a cancelled or late
    /// response can't leave the store stuck or overwrite newer results.
    @ObservationIgnored private var generation = 0

    init(section: PlexSection) {
        self.section = section
    }

    var hasMore: Bool { totalSize.map { items.count < $0 } ?? true }

    func reload(client: PlexClient) async {
        generation += 1
        await fetch(start: 0, client: client, generation: generation)
    }

    func loadNextPage(client: PlexClient) async {
        guard hasLoaded, hasMore, !isLoading else { return }
        await fetch(start: items.count, client: client, generation: generation)
    }

    private func fetch(start: Int, client: PlexClient, generation current: Int) async {
        isLoading = true
        defer { if current == generation { isLoading = false } }
        do {
            let list = try await client.items(in: section, sort: .title, page: .init(start: start, size: Self.pageSize))
            guard current == generation else { return }
            if start == 0 {
                items = list.items
            } else {
                let known = Set(items.map(\.id))
                items += list.items.filter { !known.contains($0.id) }
            }
            totalSize = list.totalSize ?? items.count
            error = nil
            hasLoaded = true
        } catch PlexError.cancelled {
            return
        } catch {
            guard current == generation else { return }
            self.error = error as? PlexError ?? .badResponse
            hasLoaded = true
        }
    }
}
