import Foundation
import Observation

/// One library's items in the chosen order, optionally one genre, loaded a page at a time.
@Observable
final class BrowseStore {
    static let pageSize = 120

    let section: PlexSection
    private(set) var sort: LibrarySort
    /// Only this genre's titles; `nil` for the whole library.
    private(set) var genre: PlexGenre?
    /// The library's genres, for the Genre menu, and how many titles each has once counted.
    private(set) var genres: [PlexGenre] = []
    private(set) var genreCounts: [String: Int] = [:]
    private(set) var items: [PlexItem] = []
    private(set) var totalSize: Int?
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var error: PlexError?

    @ObservationIgnored var context: () -> PlexContext? = { nil }
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var genreTask: Task<Void, Never>?
    @ObservationIgnored private var genreGeneration = 0
    /// Each reload supersedes any request still in flight, so a cancelled or late
    /// response can't leave the store stuck or overwrite newer results.
    @ObservationIgnored private var generation = 0

    init(section: PlexSection, sort: LibrarySort = .default) {
        self.section = section
        self.sort = sort
    }

    /// Changing the order reloads from the first page, since Plex does the sorting.
    func setSort(_ newSort: LibrarySort) {
        guard newSort != sort else { return }
        sort = newSort
        if hasLoaded || task != nil { reload() }
    }

    /// Filtering happens on the server, so a new genre reloads from the first page.
    func setGenre(_ newGenre: PlexGenre?) {
        guard newGenre != genre else { return }
        genre = newGenre
        if hasLoaded || task != nil { reload() }
    }

    func loadGenresIfNeeded() {
        guard genres.isEmpty, genreTask == nil else { return }
        loadGenres()
    }

    /// Loads the genre list, then each genre's count. Counting is one small request per genre
    /// (only the totals come back); a genre that fails to count is shown without one.
    func loadGenres() {
        guard let client = context()?.client else { return }
        genreTask?.cancel()
        genreGeneration += 1
        let current = genreGeneration
        let section = section
        genreTask = Task { [weak self] in
            let genres = try? await client.genres(in: section)
            guard let self, current == genreGeneration else { return }
            guard let genres else {
                genreTask = nil   // try again next time the library opens
                return
            }
            self.genres = genres
            let counts = await withTaskGroup(of: (String, Int?).self) { group in
                for genre in genres {
                    group.addTask { (genre.key, try? await client.itemCount(in: section, genre: genre)) }
                }
                var counts: [String: Int] = [:]
                for await (key, count) in group { counts[key] = count }
                return counts
            }
            guard current == genreGeneration else { return }
            genreCounts = counts
            genreTask = nil
        }
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
        let sort = sort
        let genre = genre
        isLoading = true
        task = Task { [weak self] in
            let result: Result<PlexItemList, PlexError>
            do {
                result = .success(try await client.items(in: section, sort: sort, genre: genre, page: .init(start: offset, size: Self.pageSize)))
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
