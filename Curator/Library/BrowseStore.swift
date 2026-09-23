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

    @ObservationIgnored var context: () -> PlexContext? = { nil }
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Each reload supersedes any request still in flight, so a cancelled or late
    /// response can't leave the store stuck or overwrite newer results.
    @ObservationIgnored private var generation = 0

    init(section: PlexSection) {
        self.section = section
    }

    var hasMore: Bool { totalSize.map { items.count < $0 } ?? true }

    func loadIfNeeded() {
        guard !hasLoaded, task == nil else { return }
        reload()
    }

    func reload() {
        task?.cancel()
        generation += 1
        start(at: 0)
    }

    func loadNextPage() {
        guard hasLoaded, hasMore, !isLoading else { return }
        start(at: items.count)
    }

    private func start(at offset: Int) {
        guard let client = context()?.client else { return }
        let current = generation
        let section = section
        isLoading = true
        task = Task { [weak self] in
            let result: Result<PlexItemList, PlexError>
            do {
                result = .success(try await client.items(in: section, sort: .title, page: .init(start: offset, size: Self.pageSize)))
            } catch {
                result = .failure(error as? PlexError ?? .badResponse)
            }
            self?.finish(result, offset: offset, generation: current)
        }
    }

    private func finish(_ result: Result<PlexItemList, PlexError>, offset: Int, generation current: Int) {
        guard current == generation else { return }
        task = nil
        isLoading = false
        switch result {
        case .success(let list):
            if offset == 0 {
                items = list.items
            } else {
                let known = Set(items.map(\.id))
                items += list.items.filter { !known.contains($0.id) }
            }
            totalSize = list.totalSize ?? items.count
            error = nil
            hasLoaded = true
        case .failure(.cancelled):
            break
        case .failure(let failure):
            error = failure
            hasLoaded = true
        }
    }
}
