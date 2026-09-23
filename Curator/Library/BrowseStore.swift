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
    private(set) var error: PlexError?

    init(section: PlexSection) {
        self.section = section
    }

    var hasMore: Bool { totalSize.map { items.count < $0 } ?? true }

    func reload(client: PlexClient) async {
        items = []
        totalSize = nil
        await loadNextPage(client: client)
    }

    func loadNextPage(client: PlexClient) async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await client.items(in: section, sort: .title, page: .init(start: items.count, size: Self.pageSize))
            let known = Set(items.map(\.id))
            items += list.items.filter { !known.contains($0.id) }
            totalSize = list.totalSize ?? items.count
            error = nil
        } catch PlexError.cancelled {
            return
        } catch {
            self.error = error as? PlexError ?? .badResponse
        }
    }
}
