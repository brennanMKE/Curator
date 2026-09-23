import Foundation
import os

nonisolated struct TMDBClient: Sendable {
    static let baseURL = URL(string: "https://api.themoviedb.org/3")!
    static let imageBaseURL = URL(string: "https://image.tmdb.org/t/p")!

    /// TMDB issues two kinds of credential: a short v3 API key sent as a query parameter,
    /// and a v4 read access token (a JWT) sent as a bearer token. Either works for v3 endpoints.
    enum Credential: Sendable, Equatable {
        case apiKey(String)
        case bearer(String)

        init?(_ raw: String) {
            let value = raw.trimmed
            guard !value.isEmpty else { return nil }
            if value.hasPrefix("eyJ") && value.split(separator: ".").count == 3 {
                self = .bearer(value)
            } else {
                self = .apiKey(value)
            }
        }
    }

    enum MediaType: String, Sendable {
        case movie
        case tv
    }

    /// Image paths for one title; either can be missing.
    struct Images: Codable, Sendable, Equatable {
        let posterPath: String?
        let backdropPath: String?

        enum CodingKeys: String, CodingKey {
            case posterPath = "poster_path"
            case backdropPath = "backdrop_path"
        }
    }

    /// TMDB's published image widths.
    enum ImageSize: String, Sendable {
        case poster = "w342"
        case backdrop = "w1280"
    }

    let credential: Credential
    var session: URLSession = .shared

    /// Confirms the credential is accepted.
    func validate() async throws {
        _ = try await get("authentication")
    }

    func images(for id: Int, type: MediaType) async throws -> Images {
        let data = try await get("\(type.rawValue)/\(id)")
        do {
            return try JSONDecoder().decode(Images.self, from: data)
        } catch {
            throw TMDBError.badResponse
        }
    }

    static func imageURL(path: String, size: ImageSize) -> URL {
        imageBaseURL.appending(path: size.rawValue).appending(path: path)
    }

    func request(_ path: String, query: [URLQueryItem] = []) -> URLRequest {
        var url = Self.baseURL.appending(path: path)
        var items = query
        if case .apiKey(let key) = credential {
            items.append(URLQueryItem(name: "api_key", value: key))
        }
        if !items.isEmpty { url.append(queryItems: items) }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if case .bearer(let token) = credential {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func get(_ path: String) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request(path))
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            Log.tmdb.error("GET \(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw TMDBError.unreachable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw TMDBError.badResponse }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw TMDBError.rejected
        case 404: throw TMDBError.notFound
        default:
            Log.tmdb.error("GET \(path, privacy: .public) returned \(http.statusCode)")
            throw TMDBError.http(http.statusCode)
        }
    }
}

nonisolated enum TMDBError: LocalizedError, Equatable {
    case rejected
    case notFound
    case unreachable(String)
    case http(Int)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .rejected: "TMDB rejected the key"
        case .notFound: "TMDB has no entry for this title"
        case .unreachable(let message): "Couldn't reach TMDB — \(message)"
        case .http(let status): "TMDB returned HTTP \(status)"
        case .badResponse: "TMDB sent a response Curator couldn't read"
        }
    }
}
