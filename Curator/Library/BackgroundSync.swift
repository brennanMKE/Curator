import SwiftUI

/// Keeps the connection, the TMDB check and Recently Added current for the whole app.
/// Attached to the menu bar label, which lives as long as the app does, so polling
/// continues with the main window closed.
struct BackgroundSync: ViewModifier {
    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(TMDBStore.self) private var tmdb
    @Environment(RecentStore.self) private var recent

    static let pollInterval: Duration = .seconds(60)

    func body(content: Content) -> some View {
        content
            // Reconnect whenever the address or token changes, after typing settles.
            .task(id: settings.plexConnectionKey) {
                if library.lastRefreshed != nil || library.status != .notConfigured {
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !Task.isCancelled else { return }
                }
                await library.refresh(using: settings)
            }
            // Check the TMDB key whenever it changes; artwork uses Plex until it's valid.
            .task(id: settings.tmdbKey.trimmed) {
                if tmdb.status != .off {
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !Task.isCancelled else { return }
                }
                await tmdb.validate(using: settings)
            }
            // Load on every connect, then poll so imports show up on their own.
            .task(id: library.revision) {
                guard library.status == .connected, let client = settings.plexClient else { return }
                await recent.load(client: client, sections: library.sections, reset: !recent.hasLoaded)
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.pollInterval)
                    guard !Task.isCancelled, library.status == .connected, let client = settings.plexClient else { return }
                    await recent.load(client: client, sections: library.sections)
                    await library.refreshCounts(using: client)
                }
            }
    }
}
