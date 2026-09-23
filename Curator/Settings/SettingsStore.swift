import Foundation
import Observation

/// Connection settings. The server address lives in UserDefaults; secrets live in the Keychain.
@Observable
final class SettingsStore {
    static let defaultServerAddress = "http://joe:32400"

    var serverAddress: String {
        didSet { defaults.set(serverAddress, forKey: Keys.serverAddress) }
    }

    var plexToken: String {
        didSet { Keychain.set(plexToken.trimmed, for: Keys.plexToken) }
    }

    var tmdbKey: String {
        didSet { Keychain.set(tmdbKey.trimmed, for: Keys.tmdbKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        serverAddress = defaults.string(forKey: Keys.serverAddress) ?? Self.defaultServerAddress
        plexToken = Keychain.string(for: Keys.plexToken) ?? ""
        tmdbKey = Keychain.string(for: Keys.tmdbKey) ?? ""
    }

    var serverURL: URL? { PlexServerURL.normalize(serverAddress) }

    var isPlexConfigured: Bool { serverURL != nil && !plexToken.trimmed.isEmpty }

    var plexClient: PlexClient? {
        guard let serverURL, !plexToken.trimmed.isEmpty else { return nil }
        return PlexClient(baseURL: serverURL, token: plexToken.trimmed)
    }

    var tmdbClient: TMDBClient? {
        TMDBClient.Credential(tmdbKey).map { TMDBClient(credential: $0) }
    }

    /// Changes whenever the Plex connection details change; drives automatic reconnects.
    var plexConnectionKey: String { "\(serverURL?.absoluteString ?? "")\n\(plexToken.trimmed)" }

    private enum Keys {
        static let serverAddress = "plexServerAddress"
        static let plexToken = "plex-token"
        static let tmdbKey = "tmdb-key"
    }
}

extension String {
    nonisolated var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
