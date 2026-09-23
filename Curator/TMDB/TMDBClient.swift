import Foundation
import os

nonisolated struct TMDBClient: Sendable {
    static let baseURL = URL(string: "https://api.themoviedb.org/3")!

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

    let credential: Credential
    var session: URLSession = .shared

    /// Confirms the credential is accepted.
    func validate() async throws {
        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await session.data(for: request("authentication"))
        } catch let error as URLError {
            Log.tmdb.error("Validate failed: \(error.localizedDescription, privacy: .public)")
            throw TMDBError.unreachable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw TMDBError.http(0) }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw TMDBError.rejected
        default: throw TMDBError.http(http.statusCode)
        }
    }

    func request(_ path: String, query: [URLQueryItem] = []) -> URLRequest {
        var url = Self.baseURL.appending(path: path)
        var items = query
        if case .apiKey(let key) = credential {
            items.append(URLQueryItem(name: "api_key", value: key))
        }
        if !items.isEmpty { url.append(queryItems: items) }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if case .bearer(let token) = credential {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

nonisolated enum TMDBError: LocalizedError, Equatable {
    case rejected
    case unreachable(String)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .rejected: "TMDB rejected the key"
        case .unreachable(let message): "Couldn't reach TMDB — \(message)"
        case .http(let status): "TMDB returned HTTP \(status)"
        }
    }
}
