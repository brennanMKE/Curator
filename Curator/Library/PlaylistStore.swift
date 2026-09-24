import Foundation
import Observation
import os

/// What a playlist store needs from the connection: a client and the server's identity,
/// which Plex needs to address library items when adding them to a playlist.
nonisolated struct PlaylistContext: Sendable {
    let client: PlexClient
    let machineIdentifier: String
}

/// One change's outcome, shown as a banner. `undo` is set when the change can be reversed.
struct PlaylistEvent: Identifiable, Equatable {
    enum Kind: Equatable { case success, info, failure }

    struct Undo: Equatable {
        let playlistID: String
        let playlistItemIDs: [String]
    }

    let id = UUID()
    let kind: Kind
    let message: String
    var undo: Undo?
}

/// Video playlists on the Plex server, and every change Curator makes to them.
///
/// Views send intents (`add`, `create`, `remove`, `move`, `rename`, `delete`, `undo`); each
/// runs its own task and reports one `event`. Plex doesn't update a playlist's `updatedAt`
/// when it changes, so "recently changed" comes from `activity`, which Curator records per
/// server, falling back to Plex's dates for playlists changed elsewhere.
@Observable
final class PlaylistStore {
    static let recentCount = 3
    static let sidebarCount = 5
    static let eventLifetime: Duration = .seconds(4)

    private(set) var playlists: [PlexPlaylist] = []
    private(set) var hasLoaded = false
    /// Entries of playlists that have been opened, in order.
    private(set) var entries: [String: [PlexItem]] = [:]
    private(set) var event: PlaylistEvent?
    /// When Curator last created or changed each playlist, by rating key.
    private(set) var activity: [String: Date] = [:]

    @ObservationIgnored var context: () -> PlaylistContext? = { nil }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var activityServer: String?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Reading

    /// Most recently changed first.
    var byRecency: [PlexPlaylist] {
        playlists.sorted { lastChanged($0) > lastChanged($1) }
    }

    /// The shortcuts in the Add to Playlist menu.
    var recent: [PlexPlaylist] { Array(byRecency.prefix(Self.recentCount)) }

    var alphabetical: [PlexPlaylist] {
        playlists.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func lastChanged(_ playlist: PlexPlaylist) -> Date {
        activity[playlist.ratingKey] ?? [playlist.updatedAt, playlist.addedAt].compactMap(\.self).max() ?? .distantPast
    }

    func playlist(_ id: String) -> PlexPlaylist? {
        playlists.first { $0.id == id }
    }

    // MARK: Intents

    /// Reloads the list; called by AppModel after every connect and after changes.
    func reload() {
        guard let context = context() else { return }
        loadActivity(for: context.machineIdentifier)
        generation += 1
        let current = generation
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            do {
                let playlists = try await context.client.playlists()
                guard let self, current == generation else { return }
                if self.playlists != playlists { self.playlists = playlists }
                if !hasLoaded { hasLoaded = true }
            } catch PlexError.cancelled {
                return
            } catch {
                guard let self, current == generation else { return }
                if !hasLoaded { hasLoaded = true }
                Log.plex.error("Loading playlists failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Loads a playlist's entries, for its detail view.
    func loadEntries(of playlistID: String) {
        guard let context = context() else { return }
        Task { [weak self] in
            guard let entries = try? await context.client.playlistItems(playlistID), let self else { return }
            if self.entries[playlistID] != entries { self.entries[playlistID] = entries }
        }
    }

    func add(_ item: PlaylistCandidate, to playlist: PlexPlaylist) {
        guard let context = context() else { return }
        Task { [weak self] in
            do {
                let added = try await context.client.addToPlaylist(playlist.id, ratingKeys: [item.ratingKey], machineIdentifier: context.machineIdentifier)
                guard let self else { return }
                touch(playlist.id)
                if added == 0 {
                    report(.info, "\(item.title) is already in \(playlist.title)")
                    return
                }
                // Refresh the entries to learn the new entry's ID, which Undo needs.
                let entries = try await context.client.playlistItems(playlist.id)
                self.entries[playlist.id] = entries
                let newEntries = entries.filter { $0.ratingKey == item.ratingKey }.suffix(added).compactMap(\.playlistItemID)
                report(.success, "Added \(item.title) to \(playlist.title)",
                       undo: newEntries.isEmpty ? nil : .init(playlistID: playlist.id, playlistItemIDs: Array(newEntries)))
                reload()
            } catch {
                self?.report(.failure, "Couldn't add \(item.title): \(error.localizedDescription)")
            }
        }
    }

    func create(named name: String, with item: PlaylistCandidate) {
        let title = name.trimmed
        guard !title.isEmpty, let context = context() else { return }
        Task { [weak self] in
            do {
                let playlist = try await context.client.createPlaylist(title: title, ratingKeys: [item.ratingKey], machineIdentifier: context.machineIdentifier)
                guard let self else { return }
                touch(playlist.id)
                if !playlists.contains(where: { $0.id == playlist.id }) { playlists.append(playlist) }
                report(.success, "Created \(playlist.title) with \(item.title)")
                reload()
            } catch {
                self?.report(.failure, "Couldn't create \(title): \(error.localizedDescription)")
            }
        }
    }

    func remove(_ entry: PlexItem, from playlist: PlexPlaylist) {
        guard let entryID = entry.playlistItemID, let context = context() else { return }
        entries[playlist.id]?.removeAll { $0.playlistItemID == entryID }   // shown at once
        Task { [weak self] in
            do {
                try await context.client.removeFromPlaylist(playlist.id, playlistItemID: entryID)
                guard let self else { return }
                touch(playlist.id)
                report(.success, "Removed \(entry.displayTitle) from \(playlist.title)")
                reload()
            } catch {
                guard let self else { return }
                report(.failure, "Couldn't remove \(entry.displayTitle): \(error.localizedDescription)")
                loadEntries(of: playlist.id)
            }
        }
    }

    /// Reorders like `List.onMove`: `source` holds one row, `destination` is its new index
    /// in the original order.
    func move(in playlist: PlexPlaylist, from source: IndexSet, to destination: Int) {
        guard var list = entries[playlist.id], let from = source.first, source.count == 1,
              let entryID = list[from].playlistItemID, let context = context() else { return }
        // Same result as List.onMove's move(fromOffsets:toOffset:), without importing SwiftUI.
        let moving = list.remove(at: from)
        list.insert(moving, at: destination > from ? destination - 1 : destination)
        guard let newIndex = list.firstIndex(where: { $0.playlistItemID == entryID }) else { return }
        let after = newIndex == 0 ? nil : list[newIndex - 1].playlistItemID
        entries[playlist.id] = list   // shown at once
        Task { [weak self] in
            do {
                try await context.client.movePlaylistItem(playlist.id, playlistItemID: entryID, after: after)
                self?.touch(playlist.id)
            } catch {
                guard let self else { return }
                report(.failure, "Couldn't reorder \(playlist.title): \(error.localizedDescription)")
                loadEntries(of: playlist.id)
            }
        }
    }

    func rename(_ playlist: PlexPlaylist, to name: String) {
        let title = name.trimmed
        guard !title.isEmpty, title != playlist.title, let context = context() else { return }
        Task { [weak self] in
            do {
                try await context.client.renamePlaylist(playlist.id, title: title)
                guard let self else { return }
                touch(playlist.id)
                report(.success, "Renamed \(playlist.title) to \(title)")
                reload()
            } catch {
                self?.report(.failure, "Couldn't rename \(playlist.title): \(error.localizedDescription)")
            }
        }
    }

    func delete(_ playlist: PlexPlaylist) {
        guard let context = context() else { return }
        Task { [weak self] in
            do {
                try await context.client.deletePlaylist(playlist.id)
                guard let self else { return }
                playlists.removeAll { $0.id == playlist.id }
                entries[playlist.id] = nil
                activity[playlist.id] = nil
                saveActivity()
                report(.success, "Deleted \(playlist.title)")
            } catch {
                self?.report(.failure, "Couldn't delete \(playlist.title): \(error.localizedDescription)")
            }
        }
    }

    /// Reverses the change the current banner describes.
    func undo() {
        guard let undo = event?.undo, let context = context() else { return }
        event = nil
        Task { [weak self] in
            do {
                for entryID in undo.playlistItemIDs {
                    try await context.client.removeFromPlaylist(undo.playlistID, playlistItemID: entryID)
                }
                guard let self else { return }
                entries[undo.playlistID]?.removeAll { undo.playlistItemIDs.contains($0.playlistItemID ?? "") }
                reload()
            } catch {
                self?.report(.failure, "Couldn't undo: \(error.localizedDescription)")
            }
        }
    }

    func dismissEvent() {
        eventTask?.cancel()
        event = nil
    }

    // MARK: Private

    private func report(_ kind: PlaylistEvent.Kind, _ message: String, undo: PlaylistEvent.Undo? = nil) {
        let event = PlaylistEvent(kind: kind, message: message, undo: undo)
        self.event = event
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            try? await Task.sleep(for: Self.eventLifetime)
            guard !Task.isCancelled, let self, self.event?.id == event.id else { return }
            self.event = nil
        }
    }

    private func touch(_ playlistID: String) {
        activity[playlistID] = .now
        saveActivity()
    }

    private var activityKey: String? { activityServer.map { "playlistActivity.\($0)" } }

    private func loadActivity(for server: String) {
        guard server != activityServer else { return }
        activityServer = server
        let stored = defaults.dictionary(forKey: "playlistActivity.\(server)") as? [String: Double] ?? [:]
        activity = stored.mapValues(Date.init(timeIntervalSince1970:))
    }

    private func saveActivity() {
        guard let activityKey else { return }
        defaults.set(activity.mapValues(\.timeIntervalSince1970), forKey: activityKey)
    }
}
