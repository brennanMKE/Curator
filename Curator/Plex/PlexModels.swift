import Foundation

/// Every Plex JSON response wraps its payload in `MediaContainer`.
nonisolated struct PlexEnvelope<Container: Decodable & Sendable>: Decodable, Sendable {
    let mediaContainer: Container

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

/// `GET /` — needs the token, unlike `/identity`, but also carries the server's name.
nonisolated struct PlexServerInfo: Decodable, Sendable, Equatable {
    let friendlyName: String?
    let version: String
    let machineIdentifier: String

    /// "1.43.4.10903-e5521bd8c" → "1.43.4"
    var shortVersion: String {
        version.split(separator: ".").prefix(3).joined(separator: ".")
    }
}

/// `GET /library/sections`
nonisolated struct PlexSectionList: Decodable, Sendable {
    let sections: [PlexSection]

    enum CodingKeys: String, CodingKey {
        case sections = "Directory"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sections = try container.decodeIfPresent([PlexSection].self, forKey: .sections) ?? []
    }
}

nonisolated struct PlexSection: Decodable, Sendable, Hashable, Identifiable {
    let key: String
    let type: String
    let title: String

    var id: String { key }

    enum Kind: Sendable {
        case movie, show, other
    }

    var kind: Kind {
        switch type {
        case "movie": .movie
        case "show": .show
        default: .other
        }
    }
}

/// Any paged listing requested with `X-Plex-Container-Size: 0`: only the counts come back.
nonisolated struct PlexCount: Decodable, Sendable {
    let size: Int
    let totalSize: Int?
}
