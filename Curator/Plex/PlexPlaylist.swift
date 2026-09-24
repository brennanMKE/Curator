import Foundation

/// A Plex video playlist (`GET /playlists?playlistType=video`).
nonisolated struct PlexPlaylist: Decodable, Sendable, Hashable, Identifiable {
    let ratingKey: String
    let title: String
    let smart: Bool
    let leafCount: Int
    /// Total runtime in milliseconds.
    let duration: Int?
    let addedAt: Date?
    /// Plex doesn't update this when items change; see PlaylistStore's activity tracking.
    let updatedAt: Date?
    /// Artwork made from the playlist's posters.
    let composite: String?

    var id: String { ratingKey }

    enum CodingKeys: String, CodingKey {
        case ratingKey, title, smart, leafCount, duration, addedAt, updatedAt, composite
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ratingKey = try c.decode(String.self, forKey: .ratingKey)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        smart = try c.decodeIfPresent(Bool.self, forKey: .smart) ?? false
        leafCount = try c.decodeIfPresent(Int.self, forKey: .leafCount) ?? 0
        duration = try c.decodeIfPresent(Int.self, forKey: .duration)
        addedAt = try c.decodeIfPresent(Double.self, forKey: .addedAt).map(Date.init(timeIntervalSince1970:))
        updatedAt = try c.decodeIfPresent(Double.self, forKey: .updatedAt).map(Date.init(timeIntervalSince1970:))
        composite = try c.decodeIfPresent(String.self, forKey: .composite)
    }
}

nonisolated struct PlexPlaylistList: Decodable, Sendable {
    let playlists: [PlexPlaylist]

    enum CodingKeys: String, CodingKey {
        case playlists = "Metadata"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playlists = try c.decodeIfPresent([PlexPlaylist].self, forKey: .playlists) ?? []
    }
}

/// The reply to adding items: how many Plex actually added (it skips duplicates).
nonisolated struct PlexPlaylistAddResult: Decodable, Sendable {
    let leafCountAdded: Int?
    let leafCountRequested: Int?
}
