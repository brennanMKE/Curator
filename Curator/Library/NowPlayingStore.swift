import Foundation
import Observation

/// A title playing (or paused) on some Plex player.
nonisolated struct NowPlaying: Equatable, Sendable {
    enum State: Sendable {
        case playing, paused
    }

    let state: State
    /// The player's name, such as "Apple TV".
    let player: String

    var description: String {
        switch state {
        case .playing: "Playing on \(player)"
        case .paused: "Paused on \(player)"
        }
    }
}

/// What's playing on the server, polled every few seconds while connected, so posters can
/// show it. Display only: Curator doesn't control playback.
@Observable
final class NowPlayingStore {
    static let pollInterval: Duration = .seconds(10)

    /// By rating key. An episode is also listed under its show, so the show's poster in TV
    /// Shows is marked too.
    private(set) var playing: [String: NowPlaying] = [:]

    @ObservationIgnored var context: () -> PlexContext? = { nil }
    @ObservationIgnored private var task: Task<Void, Never>?

    func state(for item: PlexItem) -> NowPlaying? {
        playing[item.ratingKey]
    }

    /// Starts (or restarts) polling. A failed poll keeps the last state rather than flickering.
    func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let client = self?.context()?.client else { return }
                if let sessions = try? await client.sessions() {
                    guard !Task.isCancelled else { return }
                    self?.update(Self.index(sessions))
                }
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        update([:])
    }

    /// Every poll lands here; only a real change notifies, so posters don't redraw every
    /// ten seconds.
    private func update(_ new: [String: NowPlaying]) {
        guard new != playing else { return }
        playing = new
    }

    /// When the same title is on two players, playing beats paused.
    nonisolated static func index(_ sessions: [PlexSession]) -> [String: NowPlaying] {
        var index: [String: NowPlaying] = [:]
        for session in sessions {
            let state: NowPlaying.State = session.player.state == "paused" ? .paused : .playing
            let nowPlaying = NowPlaying(state: state, player: session.player.title ?? session.player.product ?? "a Plex player")
            for key in [session.ratingKey, session.grandparentRatingKey].compactMap(\.self) {
                if index[key]?.state != .playing { index[key] = nowPlaying }
            }
        }
        return index
    }
}
