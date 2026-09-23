import Foundation
import Observation

/// Whether TMDB artwork is available. Everything that uses TMDB checks `isAvailable`
/// and falls back to Plex's own artwork otherwise.
@Observable
final class TMDBStore {
    enum Status: Equatable {
        /// No key entered.
        case off
        case checking
        case valid
        case rejected
        case unreachable(String)
    }

    private(set) var status: Status = .off
    private(set) var client: TMDBClient?

    var isAvailable: Bool { status == .valid && client != nil }

    @ObservationIgnored private var generation = 0

    func validate(using settings: SettingsStore) async {
        generation += 1
        let current = generation

        guard let client = settings.tmdbClient else {
            self.client = nil
            status = .off
            return
        }

        status = .checking
        do {
            try await client.validate()
            guard current == generation else { return }
            self.client = client
            status = .valid
        } catch is CancellationError {
            return
        } catch {
            guard current == generation else { return }
            self.client = nil
            status = error as? TMDBError == .rejected ? .rejected : .unreachable(error.localizedDescription)
        }
    }

    /// Called when an artwork request is refused, e.g. the key was revoked mid-session.
    func markRejected() {
        client = nil
        status = .rejected
    }
}
