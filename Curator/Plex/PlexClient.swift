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

    enum Sort: String, Sendable {
        case newest = "addedAt:desc"
        case title = "titleSort:asc"
    }

    func serverInfo() async throws -> PlexServerInfo {
        try await get("/", as: PlexServerInfo.self)
    }

    func sections() async throws -> [PlexSection] {
        try await get("/library/sections", as: PlexSectionList.self).sections
    }

    /// The number of top-level items (movies, shows) in a section, without fetching them.
    func itemCount(in section: PlexSection) async throws -> Int {
        let counts = try await get("/library/sections/\(section.key)/all", as: PlexCount.self, page: Page(start: 0, size: 0))
        return counts.totalSize ?? counts.size
    }

    /// A section's items in the given order. For TV, `episodes` lists episodes rather than
    /// shows, which is what "recently added" means there: a new episode doesn't re-date its show.
    func items(in section: PlexSection, sort: Sort, episodes: Bool = false, page: Page) async throws -> PlexItemList {
        var query = [URLQueryItem(name: "sort", value: sort.rawValue), URLQueryItem(name: "includeGuids", value: "1")]
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

    func request(_ path: String, query: [URLQueryItem] = [], page: Page? = nil) -> URLRequest {
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

    /// Runs off the main actor, including JSON decoding.
    @concurrent
    private func get<Container: Decodable & Sendable>(
        _ path: String,
        as _: Container.Type,
        query: [URLQueryItem] = [],
        page: Page? = nil
    ) async throws -> Container {
        let request = request(path, query: query, page: page)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code != .cancelled {
                Log.plex.error("GET \(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
            throw PlexError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw PlexError.badResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw PlexError.unauthorized
        default:
            Log.plex.error("GET \(path, privacy: .public) returned \(http.statusCode)")
            throw PlexError.http(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(PlexEnvelope<Container>.self, from: data).mediaContainer
        } catch {
            Log.plex.error("GET \(path, privacy: .public) decode failed: \(error, privacy: .public)")
            throw PlexError.badResponse
        }
    }
}

extension CharacterSet {
    /// RFC 3986 unreserved characters; everything else gets percent-encoded.
    nonisolated static let urlUnreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
