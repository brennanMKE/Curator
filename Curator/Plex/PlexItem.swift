import Foundation

/// A movie, show or episode as returned by listings, searches and `/library/metadata/{id}`.
/// Listing responses carry fewer fields than the full metadata, so nearly everything is optional.
nonisolated struct PlexItem: Decodable, Sendable, Hashable, Identifiable {
    let ratingKey: String
    let type: String
    let title: String
    let year: Int?
    let summary: String?
    let tagline: String?
    let contentRating: String?
    let audienceRating: Double?
    let duration: Int?
    let addedAt: Date?
    /// "YYYY-MM-DD" from Plex.
    let originallyAvailableAt: String?
    let thumb: String?
    let art: String?
    let librarySectionID: Int?

    // Episodes
    let grandparentTitle: String?
    let grandparentThumb: String?
    let grandparentArt: String?
    let parentIndex: Int?
    let index: Int?

    // Hub search: why this item matched ("director", "Joel Coen").
    let reason: String?
    let reasonTitle: String?

    let guids: [String]
    let genres: [String]
    let directors: [String]
    let cast: [String]
    let media: [PlexMedia]

    var id: String { ratingKey }

    enum Kind: Sendable {
        case movie, show, episode, other
    }

    var kind: Kind {
        switch type {
        case "movie": .movie
        case "show": .show
        case "episode": .episode
        default: .other
        }
    }

    var tmdbID: Int? {
        guids.lazy.compactMap { $0.hasPrefix("tmdb://") ? Int($0.dropFirst(7)) : nil }.first
    }

    /// The show's name for an episode, otherwise the title.
    var displayTitle: String { kind == .episode ? (grandparentTitle ?? title) : title }

    /// "S1E3 · Pilot" for episodes, the year for everything else.
    var displaySubtitle: String? {
        guard kind == .episode else { return year.map(String.init) }
        let code = [parentIndex.map { "S\($0)" }, index.map { "E\($0)" }].compactMap(\.self).joined()
        return code.isEmpty ? title : "\(code) · \(title)"
    }

    /// Posters are 2:3; an episode's own thumb is a 16:9 still, so use the show's poster.
    var posterPath: String? { kind == .episode ? (grandparentThumb ?? thumb) : thumb }
    var backdropPath: String? { kind == .episode ? (grandparentArt ?? art) : art }

    var filePath: String? { media.first?.parts.first?.file }

    var releaseDate: Date? {
        originallyAvailableAt.flatMap { try? Date($0, strategy: .iso8601.year().month().day()) }
    }

    enum CodingKeys: String, CodingKey {
        case ratingKey, type, title, year, summary, tagline, contentRating, audienceRating, duration
        case addedAt, originallyAvailableAt, thumb, art, librarySectionID
        case grandparentTitle, grandparentThumb, grandparentArt, parentIndex, index
        case reason, reasonTitle
        case guids = "Guid"
        case genres = "Genre"
        case directors = "Director"
        case cast = "Role"
        case media = "Media"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ratingKey = try c.decode(String.self, forKey: .ratingKey)
        type = try c.decode(String.self, forKey: .type)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        tagline = try c.decodeIfPresent(String.self, forKey: .tagline)
        contentRating = try c.decodeIfPresent(String.self, forKey: .contentRating)
        audienceRating = try c.decodeIfPresent(Double.self, forKey: .audienceRating)
        duration = try c.decodeIfPresent(Int.self, forKey: .duration)
        addedAt = try c.decodeIfPresent(Double.self, forKey: .addedAt).map(Date.init(timeIntervalSince1970:))
        originallyAvailableAt = try c.decodeIfPresent(String.self, forKey: .originallyAvailableAt)
        thumb = try c.decodeIfPresent(String.self, forKey: .thumb)
        art = try c.decodeIfPresent(String.self, forKey: .art)
        librarySectionID = try c.decodeIfPresent(Int.self, forKey: .librarySectionID)
        grandparentTitle = try c.decodeIfPresent(String.self, forKey: .grandparentTitle)
        grandparentThumb = try c.decodeIfPresent(String.self, forKey: .grandparentThumb)
        grandparentArt = try c.decodeIfPresent(String.self, forKey: .grandparentArt)
        parentIndex = try c.decodeIfPresent(Int.self, forKey: .parentIndex)
        index = try c.decodeIfPresent(Int.self, forKey: .index)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        reasonTitle = try c.decodeIfPresent(String.self, forKey: .reasonTitle)
        guids = try c.decodeIfPresent([GuidTag].self, forKey: .guids)?.map(\.id) ?? []
        genres = try c.decodeIfPresent([Tag].self, forKey: .genres)?.map(\.tag) ?? []
        directors = try c.decodeIfPresent([Tag].self, forKey: .directors)?.map(\.tag) ?? []
        cast = try c.decodeIfPresent([Tag].self, forKey: .cast)?.map(\.tag) ?? []
        media = try c.decodeIfPresent([PlexMedia].self, forKey: .media) ?? []
    }

    private struct Tag: Decodable { let tag: String }
    private struct GuidTag: Decodable { let id: String }
}

nonisolated struct PlexMedia: Decodable, Sendable, Hashable {
    let videoResolution: String?
    let videoCodec: String?
    let audioCodec: String?
    let audioChannels: Int?
    let container: String?
    let width: Int?
    let height: Int?
    let parts: [PlexPart]

    enum CodingKeys: String, CodingKey {
        case videoResolution, videoCodec, audioCodec, audioChannels, container, width, height
        case parts = "Part"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        videoResolution = try c.decodeIfPresent(String.self, forKey: .videoResolution)
        videoCodec = try c.decodeIfPresent(String.self, forKey: .videoCodec)
        audioCodec = try c.decodeIfPresent(String.self, forKey: .audioCodec)
        audioChannels = try c.decodeIfPresent(Int.self, forKey: .audioChannels)
        container = try c.decodeIfPresent(String.self, forKey: .container)
        width = try c.decodeIfPresent(Int.self, forKey: .width)
        height = try c.decodeIfPresent(Int.self, forKey: .height)
        parts = try c.decodeIfPresent([PlexPart].self, forKey: .parts) ?? []
    }
}

nonisolated struct PlexPart: Decodable, Sendable, Hashable {
    let file: String?
    let size: Int64?
}

/// Any listing of items: a section's `/all`, `/library/metadata/{id}`.
nonisolated struct PlexItemList: Decodable, Sendable {
    let items: [PlexItem]
    let size: Int
    let totalSize: Int?

    enum CodingKeys: String, CodingKey {
        case items = "Metadata"
        case size, totalSize
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([PlexItem].self, forKey: .items) ?? []
        size = try c.decodeIfPresent(Int.self, forKey: .size) ?? items.count
        totalSize = try c.decodeIfPresent(Int.self, forKey: .totalSize)
    }
}

/// `GET /hubs/search`: one hub per result type (movies, shows, directors, actors…).
nonisolated struct PlexHubList: Decodable, Sendable {
    let hubs: [PlexHub]

    enum CodingKeys: String, CodingKey {
        case hubs = "Hub"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hubs = try c.decodeIfPresent([PlexHub].self, forKey: .hubs) ?? []
    }
}

nonisolated struct PlexHub: Decodable, Sendable {
    let type: String
    let items: [PlexItem]

    enum CodingKeys: String, CodingKey {
        case type
        case items = "Metadata"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        items = try c.decodeIfPresent([PlexItem].self, forKey: .items) ?? []
    }
}
