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

    /// The number of top-level items (movies, shows) in a section, without fetching them.
    func itemCount(in section: PlexSection) async throws -> Int {
        let counts = try await get("/library/sections/\(section.key)/all", as: PlexCount.self, page: Page(start: 0, size: 0))
        return counts.totalSize ?? counts.size
    }

    func request(_ path: String, query: [URLQueryItem] = [], page: Page? = nil) -> URLRequest {
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        request.setValue("Curator", forHTTPHeaderField: "X-Plex-Product")
        if let page {
            request.setValue(String(page.start), forHTTPHeaderField: "X-Plex-Container-Start")
            request.setValue(String(page.size), forHTTPHeaderField: "X-Plex-Container-Size")
        }
        return request
    }

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
            Log.plex.error("GET \(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
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
