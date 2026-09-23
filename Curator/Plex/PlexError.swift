import Foundation

nonisolated enum PlexError: LocalizedError, Equatable {
    case notConfigured
    case invalidServerURL
    case unauthorized
    case insecureConnectionBlocked
    case unreachable(String)
    case http(Int)
    case badResponse

    init(_ error: URLError) {
        switch error.code {
        case .appTransportSecurityRequiresSecureConnection:
            self = .insecureConnectionBlocked
        case .userAuthenticationRequired:
            self = .unauthorized
        default:
            self = .unreachable(error.localizedDescription)
        }
    }

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Plex isn't set up yet"
        case .invalidServerURL: "The server address isn't a valid URL"
        case .unauthorized: "Plex rejected the token"
        case .insecureConnectionBlocked: "macOS blocked plain HTTP to this server"
        case .unreachable(let message): "Couldn't reach the Plex server — \(message)"
        case .http(let status): "Plex returned HTTP \(status)"
        case .badResponse: "Plex sent a response Curator couldn't read"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notConfigured:
            "Add the server address and token in Settings."
        case .invalidServerURL:
            "Use a host name like joe, or a full URL like http://joe:32400."
        case .unauthorized:
            "Copy the token again from joe and paste it into Settings."
        case .insecureConnectionBlocked:
            "Plain HTTP is only allowed to local hosts. Use joe, joe.local or an IP address, or switch to https."
        case .unreachable:
            "Check the address and that joe is awake. If this is the first launch, allow Curator in System Settings › Privacy & Security › Local Network."
        case .http, .badResponse:
            "Try again. If it keeps happening, check the Plex server's logs."
        }
    }
}
