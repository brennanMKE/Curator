import Foundation

/// Talks to the Plex server directly from the test runner, to set up playlists and to delete
/// every playlist a test made, even when the test fails. Uses the same values the app gets.
struct PlexTestAPI {
    static let playlistPrefix = "Curator UI Test"

    let base: URL
    let token: String

    init?(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard let url = environment["CURATOR_PLEX_URL"].flatMap(URL.init(string:)),
              let token = environment["CURATOR_PLEX_TOKEN"], !token.isEmpty else { return nil }
        base = url
        self.token = token
    }

    static func uniqueName() -> String {
        "\(playlistPrefix) \(UUID().uuidString.prefix(6))"
    }

    func json(_ method: String = "GET", _ path: String, _ query: [String: String] = [:]) async throws -> [String: Any] {
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        let (data, _) = try await URLSession.shared.data(for: request)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return object["MediaContainer"] as? [String: Any] ?? [:]
    }

    func playlists() async throws -> [(id: String, title: String, count: Int)] {
        let container = try await json("/playlists", ["playlistType": "video"])
        return (container["Metadata"] as? [[String: Any]] ?? []).map {
            ($0["ratingKey"] as? String ?? "", $0["title"] as? String ?? "", $0["leafCount"] as? Int ?? 0)
        }
    }

    func playlist(named title: String) async throws -> (id: String, title: String, count: Int)? {
        try await playlists().first { $0.title == title }
    }

    /// Deletes every playlist whose name starts with the test prefix.
    func deleteTestPlaylists() async {
        guard let all = try? await playlists() else { return }
        for playlist in all where playlist.title.hasPrefix(Self.playlistPrefix) {
            _ = try? await json("DELETE", "/playlists/\(playlist.id)")
        }
    }

    /// The first few movies' rating keys, in title order.
    func movieRatingKeys(_ count: Int) async throws -> [String] {
        let sections = try await json("/library/sections")["Directory"] as? [[String: Any]] ?? []
        guard let movies = sections.first(where: { $0["type"] as? String == "movie" })?["key"] as? String else { return [] }
        let items = try await json("/library/sections/\(movies)/all", ["sort": "titleSort:asc"])["Metadata"] as? [[String: Any]] ?? []
        return items.prefix(count).compactMap { $0["ratingKey"] as? String }
    }

    func createPlaylist(named title: String, ratingKey: String) async throws {
        let machine = try await json("/")["machineIdentifier"] as? String ?? ""
        _ = try await json("POST", "/playlists", [
            "type": "video", "title": title, "smart": "0",
            "uri": "server://\(machine)/com.plexapp.plugins.library/library/metadata/\(ratingKey)",
        ])
    }
}
