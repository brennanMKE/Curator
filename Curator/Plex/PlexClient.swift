import Foundation
import os

/// A thin async client for Plex Media Server's HTTP API, always requesting JSON.
nonisolated struct PlexClient: Sendable {
    let baseURL: URL
    let token: String
    var session: URLSession = .shared

    /// Paging needs both headers; `X-Plex-Container-Size` alone is silently ignored.
    struct Page: Sendable, Equatable {
        var start: Int
        var size: Int
    }

    func serverInfo() async throws -> PlexServerInfo {
        try await get("/", as: PlexServerInfo.self)
    }

    func sections() async throws -> [PlexSection] {
        try await get("/library/sections", as: PlexSectionList.self).sections
    }

    /// The number of top-level items (movies, shows) in a section, or in one of its genres,
    /// without fetching them.
    func itemCount(in section: PlexSection, genre: PlexGenre? = nil) async throws -> Int {
        let query = genre.map { [URLQueryItem(name: "genre", value: $0.key)] } ?? []
        let counts = try await get("/library/sections/\(section.key)/all", as: PlexCount.self, query: query, page: Page(start: 0, size: 0))
        return counts.totalSize ?? counts.size
    }

    /// The genres in a section, A to Z.
    func genres(in section: PlexSection) async throws -> [PlexGenre] {
        try await get("/library/sections/\(section.key)/genre", as: PlexGenreList.self).genres
    }

    /// A section's items in the given order, optionally only one genre (Plex filters). For TV,
    /// `episodes` lists episodes rather than shows, which is what "recently added" means there:
    /// a new episode doesn't re-date its show.
    func items(in section: PlexSection, sort: LibrarySort, genre: PlexGenre? = nil, episodes: Bool = false, page: Page) async throws -> PlexItemList {
        var query = [URLQueryItem(name: "sort", value: sort.plexValue), URLQueryItem(name: "includeGuids", value: "1")]
        if let genre { query.append(URLQueryItem(name: "genre", value: genre.key)) }
        if episodes { query.append(URLQueryItem(name: "type", value: "4")) }
        return try await get("/library/sections/\(section.key)/all", as: PlexItemList.self, query: query, page: page)
    }

    /// Word-prefix title search within one section. Complete, but title-only.
    func search(title: String, in section: PlexSection) async throws -> [PlexItem] {
        let query = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "includeGuids", value: "1")]
        return try await get("/library/sections/\(section.key)/all", as: PlexItemList.self, query: query).items
    }

    /// Fuzzy search across everything, including cast and crew. Ranked and truncated, so it
    /// can leave out titles the section search finds.
    func hubSearch(_ text: String, limit: Int = 20) async throws -> [PlexHub] {
        let query = [URLQueryItem(name: "query", value: text), URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "includeGuids", value: "1")]
        return try await get("/hubs/search", as: PlexHubList.self, query: query).hubs
    }

    /// Full metadata for one item, including media and file details.
    func item(ratingKey: String) async throws -> PlexItem? {
        let query = [URLQueryItem(name: "includeGuids", value: "1")]
        return try await get("/library/metadata/\(ratingKey)", as: PlexItemList.self, query: query).items.first
    }

    /// What every player is streaming right now.
    func sessions() async throws -> [PlexSession] {
        try await get("/status/sessions", as: PlexSessionList.self).sessions
    }

    // MARK: Playlists

    func playlists() async throws -> [PlexPlaylist] {
        try await get("/playlists", as: PlexPlaylistList.self, query: [URLQueryItem(name: "playlistType", value: "video")]).playlists
    }

    func playlistItems(_ playlistID: String) async throws -> [PlexItem] {
        try await get("/playlists/\(playlistID)/items", as: PlexItemList.self, query: [URLQueryItem(name: "includeGuids", value: "1")]).items
    }

    /// Plex won't create an empty playlist, so it always starts with at least one item.
    func createPlaylist(title: String, ratingKeys: [String], machineIdentifier: String) async throws -> PlexPlaylist {
        let query = [
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "smart", value: "0"),
            URLQueryItem(name: "uri", value: Self.itemsURI(ratingKeys, machineIdentifier: machineIdentifier)),
        ]
        guard let playlist = try await send("POST", "/playlists", as: PlexPlaylistList.self, query: query).playlists.first else {
            throw PlexError.badResponse
        }
        return playlist
    }

    /// Returns how many items Plex added; it skips ones already in the playlist.
    func addToPlaylist(_ playlistID: String, ratingKeys: [String], machineIdentifier: String) async throws -> Int {
        let query = [URLQueryItem(name: "uri", value: Self.itemsURI(ratingKeys, machineIdentifier: machineIdentifier))]
        return try await send("PUT", "/playlists/\(playlistID)/items", as: PlexPlaylistAddResult.self, query: query).leafCountAdded ?? 0
    }

    func removeFromPlaylist(_ playlistID: String, playlistItemID: String) async throws {
        try await send("DELETE", "/playlists/\(playlistID)/items/\(playlistItemID)")
    }

    /// Moves an entry to just after `after`, or to the top when `after` is nil.
    func movePlaylistItem(_ playlistID: String, playlistItemID: String, after: String?) async throws {
        let query = after.map { [URLQueryItem(name: "after", value: $0)] } ?? []
        try await send("PUT", "/playlists/\(playlistID)/items/\(playlistItemID)/move", query: query)
    }

    func renamePlaylist(_ playlistID: String, title: String) async throws {
        try await send("PUT", "/playlists/\(playlistID)", query: [URLQueryItem(name: "title", value: title)])
    }

    func deletePlaylist(_ playlistID: String) async throws {
        try await send("DELETE", "/playlists/\(playlistID)")
    }

    /// `server://{machine}/com.plexapp.plugins.library/library/metadata/{key1},{key2}`
    static func itemsURI(_ ratingKeys: [String], machineIdentifier: String) -> String {
        "server://\(machineIdentifier)/com.plexapp.plugins.library/library/metadata/\(ratingKeys.joined(separator: ","))"
    }

    /// The playlist's page in Plex Web.
    func webURL(forPlaylist playlistID: String, machineIdentifier: String) -> URL? {
        let key = Self.encode("/playlists/\(playlistID)")
        return URL(string: baseURL.absoluteString + "/web/index.html#!/server/\(machineIdentifier)/playlist?key=\(key)")
    }

    // MARK: Images

    /// A resized image from Plex's own artwork (`thumb`, `art`).
    func imageRequest(path: String, width: Int, height: Int) -> URLRequest {
        let query = [
            URLQueryItem(name: "width", value: String(width)),
            URLQueryItem(name: "height", value: String(height)),
            URLQueryItem(name: "minSize", value: "1"),
            URLQueryItem(name: "upscale", value: "1"),
            URLQueryItem(name: "url", value: path),
        ]
        var request = request("/photo/:/transcode", query: query)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        return request
    }

    /// The item's page in Plex Web, served by the same server.
    func webURL(for item: PlexItem, machineIdentifier: String) -> URL? {
        let key = Self.encode("/library/metadata/\(item.ratingKey)")
        return URL(string: baseURL.absoluteString + "/web/index.html#!/server/\(machineIdentifier)/details?key=\(key)")
    }

    func request(_ path: String, method: String = "GET", query: [URLQueryItem] = [], page: Page? = nil) -> URLRequest {
        var url = baseURL.appending(path: path)
        if !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            // Encode strictly: Plex needs `:` in sort keys and operator characters in filter
            // names escaped, and titles can contain `&`.
            components.percentEncodedQuery = query
                .map { "\(Self.encode($0.name))=\(Self.encode($0.value ?? ""))" }
                .joined(separator: "&")
            url = components.url ?? url
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        request.setValue("Curator", forHTTPHeaderField: "X-Plex-Product")
        if let page {
            request.setValue(String(page.start), forHTTPHeaderField: "X-Plex-Container-Start")
            request.setValue(String(page.size), forHTTPHeaderField: "X-Plex-Container-Size")
        }
        return request
    }

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlUnreserved) ?? value
    }

    private func get<Container: Decodable & Sendable>(
        _ path: String,
        as type: Container.Type,
        query: [URLQueryItem] = [],
        page: Page? = nil
    ) async throws -> Container {
        try await send("GET", path, as: type, query: query, page: page)
    }

    /// Sends a request whose reply has no body Curator needs (DELETE, move, rename).
    private func send(_ method: String, _ path: String, query: [URLQueryItem] = []) async throws {
        _ = try await data(request(path, method: method, query: query), path: path)
    }

    /// Runs off the main actor, including JSON decoding.
    @concurrent
    private func send<Container: Decodable & Sendable>(
        _ method: String,
        _ path: String,
        as _: Container.Type,
        query: [URLQueryItem] = [],
        page: Page? = nil
    ) async throws -> Container {
        let data = try await data(request(path, method: method, query: query, page: page), path: path)
        do {
            return try JSONDecoder().decode(PlexEnvelope<Container>.self, from: data).mediaContainer
        } catch {
            Log.plex.error("\(method, privacy: .public) \(path, privacy: .public) decode failed: \(error, privacy: .public)")
            throw PlexError.badResponse
        }
    }

    @concurrent
    private func data(_ request: URLRequest, path: String) async throws -> Data {
        let method = request.httpMethod ?? "GET"
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code != .cancelled {
                Log.plex.error("\(method, privacy: .public) \(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
            throw PlexError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw PlexError.badResponse }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw PlexError.unauthorized
        default:
            Log.plex.error("\(method, privacy: .public) \(path, privacy: .public) returned \(http.statusCode)")
            throw PlexError.http(http.statusCode)
        }
    }
}

extension CharacterSet {
    /// RFC 3986 unreserved characters; everything else gets percent-encoded.
    nonisolated static let urlUnreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
