import Foundation
import Observation

/// What a store needs to talk to Plex: a client and the libraries it serves.
nonisolated struct PlexContext: Sendable {
    let client: PlexClient
    let sections: [PlexSection]
}

/// Owns every long-running piece of work: connecting, checking the TMDB key, polling
/// Recently Added, and reloading what's on screen after a reconnect.
///
/// Views never start or cancel network requests. They render store state and send
/// intents (`refresh()`, `search.query = …`, `store.loadNextPage()`); each store owns its
/// tasks and tags results with a generation, so a cancelled or late response can't
/// overwrite newer state however SwiftUI recreates views.
@Observable
final class AppModel {
    let settings: SettingsStore
    let library = LibraryStore()
    let tmdb = TMDBStore()
    let recent: RecentStore
    let search = SearchStore()
    let details = ItemDetailStore()

    /// How Movies and TV Shows are ordered; one choice for both, remembered across launches.
    var librarySort: LibrarySort {
        didSet {
            guard librarySort != oldValue else { return }
            defaults.set(librarySort.storageValue, forKey: Self.librarySortKey)
            browseStores.values.forEach { $0.setSort(librarySort) }
        }
    }

    static let pollInterval: Duration = .seconds(60)
    private static let librarySortKey = "librarySort"
    /// Settings save on every keystroke; reconnect once typing settles.
    static let settingsDebounce: Duration = .milliseconds(600)

    @ObservationIgnored private var browseStores: [String: BrowseStore] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var tmdbTask: Task<Void, Never>?
    @ObservationIgnored private var connectedServerID: String?

    init(settings: SettingsStore = SettingsStore(), recent: RecentStore = RecentStore(), defaults: UserDefaults = .standard) {
        self.settings = settings
        self.recent = recent
        self.defaults = defaults
        librarySort = defaults.string(forKey: Self.librarySortKey).flatMap(LibrarySort.init(storageValue:)) ?? .default

        let context: () -> PlexContext? = { [weak self] in self?.plexContext }
        recent.context = context
        search.context = context
        details.context = context
        settings.onChange = { [weak self] change in
            switch change {
            case .plex: self?.connect(after: Self.settingsDebounce)
            case .tmdb: self?.validateTMDB(after: Self.settingsDebounce)
            }
        }

        connect(after: .zero)
        validateTMDB(after: .zero)
    }

    /// The app's model. In Debug builds, UI tests launch with `CURATOR_UI_TEST=1` to get
    /// throwaway settings seeded from `CURATOR_PLEX_URL`, `CURATOR_PLEX_TOKEN` and
    /// `CURATOR_TMDB_API_KEY`, so a test run never reads or writes the real settings.
    static func forLaunch() -> AppModel {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["CURATOR_UI_TEST"] == "1" {
            let file = FileManager.default.temporaryDirectory.appending(path: "curator-ui-test-\(UUID().uuidString).env")
            let settings = SettingsStore(fileURL: file)
            settings.serverAddress = environment["CURATOR_PLEX_URL"] ?? ""
            settings.plexToken = environment["CURATOR_PLEX_TOKEN"] ?? ""
            settings.tmdbKey = environment["CURATOR_TMDB_API_KEY"] ?? ""
            return AppModel(settings: settings)
        }
        #endif
        return AppModel()
    }

    /// Only while connected: stores treat `nil` as "nothing to load yet".
    var plexContext: PlexContext? {
        guard library.status == .connected, let client = settings.plexClient else { return nil }
        return PlexContext(client: client, sections: library.sections)
    }

    // MARK: Intents

    func refresh() {
        connect(after: .zero)
    }

    /// Reconnects and re-checks TMDB now, returning when both have finished.
    func testConnection() async {
        connect(after: .zero)
        validateTMDB(after: .zero)
        await connectTask?.value
        await tmdbTask?.value
    }

    /// The store for one library, kept across visits so it isn't reloaded each time.
    func browseStore(for section: PlexSection) -> BrowseStore {
        if let store = browseStores[section.key] { return store }
        let store = BrowseStore(section: section, sort: librarySort)
        store.context = { [weak self] in self?.plexContext }
        browseStores[section.key] = store
        return store
    }

    // MARK: Work

    private func connect(after delay: Duration) {
        connectTask?.cancel()
        pollTask?.cancel()
        connectTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            guard let self else { return }
            await library.refresh(using: settings)
            guard !Task.isCancelled else { return }
            didConnect()
        }
    }

    private func didConnect() {
        details.removeAll()
        guard library.status == .connected else { return }

        let keys = Set(library.sections.map(\.key))
        for (key, store) in browseStores {
            if keys.contains(key) { store.reload() } else { browseStores[key] = nil }
        }
        search.rerun()

        // A different server means a different library: start Recently Added over.
        let serverID = library.server?.machineIdentifier
        let reset = serverID != connectedServerID
        connectedServerID = serverID
        startPolling(reset: reset)
    }

    private func startPolling(reset: Bool) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.recent.load(reset: reset)
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled, let self else { return }
                await recent.load()
                if let client = settings.plexClient {
                    await library.refreshCounts(using: client)
                }
            }
        }
    }

    private func validateTMDB(after delay: Duration) {
        tmdbTask?.cancel()
        tmdbTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            guard let self else { return }
            await tmdb.validate(using: settings)
        }
    }
}
