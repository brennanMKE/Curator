import Foundation
import os
import Observation

/// The connection to Plex and the libraries it serves.
@Observable
final class LibraryStore {
    enum Status: Equatable {
        case notConfigured
        case connecting
        case connected
        case failed(PlexError)
    }

    struct Library: Identifiable, Hashable {
        let section: PlexSection
        /// `nil` when the count request failed; the library is still usable.
        let itemCount: Int?

        var id: String { section.id }
    }

    private(set) var status: Status = .notConfigured
    private(set) var server: PlexServerInfo?
    private(set) var libraries: [Library] = []
    private(set) var lastRefreshed: Date?
    var sections: [PlexSection] { libraries.map(\.section) }

    @ObservationIgnored private var generation = 0

    func refresh(using settings: SettingsStore) async {
        generation += 1
        let current = generation

        guard settings.serverURL != nil || settings.serverAddress.trimmed.isEmpty else {
            reset(to: .failed(.invalidServerURL))
            return
        }
        guard let client = settings.plexClient else {
            reset(to: .notConfigured)
            return
        }

        status = .connecting
        do {
            async let info = client.serverInfo()
            let sections = try await client.sections().filter { $0.kind != .other }
            let counted = await Self.count(sections, with: client)
            let server = try await info

            guard current == generation else { return }
            self.server = server
            self.libraries = counted
            self.lastRefreshed = .now
            self.status = .connected
            Log.plex.info("Connected to \(server.friendlyName ?? "Plex", privacy: .public): \(counted.count) libraries")
        } catch PlexError.cancelled {
            // Superseded by a newer connect, which owns the status now.
            return
        } catch {
            guard current == generation else { return }
            reset(to: .failed(error as? PlexError ?? .unreachable(error.localizedDescription)))
        }
    }

    /// Updates item counts without disturbing the connection state; used while polling.
    func refreshCounts(using client: PlexClient) async {
        guard status == .connected else { return }
        let counted = await Self.count(sections, with: client)
        guard status == .connected, counted.map(\.id) == libraries.map(\.id) else { return }
        libraries = counted
    }

    private func reset(to status: Status) {
        self.status = status
        server = nil
        libraries = []
    }

    /// Movies first, then TV, each in the server's order.
    private nonisolated static func count(_ sections: [PlexSection], with client: PlexClient) async -> [Library] {
        await withTaskGroup(of: (Int, Library).self) { group in
            for (index, section) in sections.enumerated() {
                group.addTask {
                    (index, Library(section: section, itemCount: try? await client.itemCount(in: section)))
                }
            }
            var results: [(Int, Library)] = []
            for await result in group { results.append(result) }
            return results
                .sorted { ($0.1.section.kind.sortOrder, $0.0) < ($1.1.section.kind.sortOrder, $1.0) }
                .map(\.1)
        }
    }
}

extension PlexSection.Kind {
    nonisolated var sortOrder: Int {
        switch self {
        case .movie: 0
        case .show: 1
        case .other: 2
        }
    }

    var systemImage: String {
        switch self {
        case .movie: "film"
        case .show: "tv"
        case .other: "folder"
        }
    }

    func itemCountLabel(_ count: Int) -> String {
        switch self {
        case .movie: count == 1 ? "1 movie" : "\(count) movies"
        case .show: count == 1 ? "1 show" : "\(count) shows"
        case .other: count == 1 ? "1 item" : "\(count) items"
        }
    }
}
