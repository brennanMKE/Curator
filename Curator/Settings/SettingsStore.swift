import Foundation
import Observation
import os

/// Connection settings, kept in a `.env` file in the app's Application Support folder
/// with the same keys as the repo's `.env.example`.
@Observable
final class SettingsStore {
    static let defaultServerAddress = "http://joe:32400"

    enum Key {
        static let serverAddress = "PLEX_URL"
        static let plexToken = "PLEX_TOKEN"
        static let tmdbKey = "TMDB_API_KEY"
        static let all = [serverAddress, plexToken, tmdbKey]
    }

    var serverAddress: String {
        didSet { save(Key.serverAddress, serverAddress) }
    }

    var plexToken: String {
        didSet { save(Key.plexToken, plexToken) }
    }

    var tmdbKey: String {
        didSet { save(Key.tmdbKey, tmdbKey) }
    }

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
        serverAddress = file[Key.serverAddress] ?? Self.defaultServerAddress
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

    /// Changes whenever the Plex connection details change; drives automatic reconnects.
    var plexConnectionKey: String { "\(serverURL?.absoluteString ?? "")\n\(plexToken.trimmed)" }

    /// Copies any of Curator's keys found in another `.env`, such as the repo's.
    /// Returns the keys that were imported.
    @discardableResult
    func importValues(from other: EnvFile) -> [String] {
        var imported: [String] = []
        if let value = other[Key.serverAddress], !value.isEmpty {
            serverAddress = value
            imported.append(Key.serverAddress)
        }
        if let value = other[Key.plexToken], !value.isEmpty {
            plexToken = value
            imported.append(Key.plexToken)
        }
        if let value = other[Key.tmdbKey], !value.isEmpty {
            tmdbKey = value
            imported.append(Key.tmdbKey)
        }
        return imported
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
