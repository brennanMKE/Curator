import Foundation
import Observation
import os

/// Connection settings, kept in a `.env` file in the app's Application Support folder
/// with the same keys as the repo's `.env.example`. Never the Keychain.
@Observable
final class SettingsStore {
    enum Key {
        static let serverAddress = "PLEX_URL"
        static let plexToken = "PLEX_TOKEN"
        static let tmdbKey = "TMDB_API_KEY"
        static let all = [serverAddress, plexToken, tmdbKey]
    }

    enum Change {
        case plex, tmdb
    }

    var serverAddress: String {
        didSet { changed(Key.serverAddress, serverAddress, from: oldValue, .plex) }
    }

    var plexToken: String {
        didSet { changed(Key.plexToken, plexToken, from: oldValue, .plex) }
    }

    var tmdbKey: String {
        didSet { changed(Key.tmdbKey, tmdbKey, from: oldValue, .tmdb) }
    }

    /// Set by `AppModel`, which reconnects or re-checks TMDB. Views don't watch settings.
    @ObservationIgnored var onChange: ((Change) -> Void)?

    @ObservationIgnored let fileURL: URL
    @ObservationIgnored private var file: EnvFile

    init(fileURL: URL = SettingsStore.defaultFileURL) {
        self.fileURL = fileURL
        do {
            file = try EnvFile(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            file = EnvFile()
        } catch {
            Log.settings.error("Reading \(fileURL.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            file = EnvFile()
        }
        serverAddress = file[Key.serverAddress] ?? ""
        plexToken = file[Key.plexToken] ?? ""
        tmdbKey = file[Key.tmdbKey] ?? ""
    }

    static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "Curator", directoryHint: .isDirectory).appending(path: ".env")
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

    /// Changes whenever the Plex connection details change.
    var plexConnectionKey: String { "\(serverURL?.absoluteString ?? "")\n\(plexToken.trimmed)" }

    private func changed(_ key: String, _ value: String, from oldValue: String, _ change: Change) {
        guard value.trimmed != oldValue.trimmed else { return }
        save(key, value)
        onChange?(change)
    }

    private func save(_ key: String, _ value: String) {
        file[key] = value.trimmed
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.text.utf8).write(to: fileURL, options: .atomic)
            // Holds a token; readable by this user only, like a hand-made .env.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            Log.settings.error("Writing \(self.fileURL.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension String {
    nonisolated var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
