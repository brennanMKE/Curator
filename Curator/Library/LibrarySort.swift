import Foundation

/// How a library is ordered. Sorting is done by Plex, so paging stays correct.
nonisolated struct LibrarySort: Sendable, Hashable {
    enum Field: String, CaseIterable, Sendable {
        case title, releaseDate, dateAdded, rating

        var label: String {
            switch self {
            case .title: "Title"
            case .releaseDate: "Release Date"
            case .dateAdded: "Date Added"
            case .rating: "Rating"
            }
        }

        /// Plex's sort key for `/library/sections/{id}/all?sort=`.
        var plexKey: String {
            switch self {
            case .title: "titleSort"
            case .releaseDate: "originallyAvailableAt"
            case .dateAdded: "addedAt"
            case .rating: "audienceRating"
            }
        }

        /// Titles read A to Z; dates and ratings read newest or highest first.
        var defaultAscending: Bool { self == .title }

        /// The order choices, in words that fit the field: (ascending, descending).
        var orderLabels: (ascending: String, descending: String) {
            switch self {
            case .title: ("A to Z", "Z to A")
            case .releaseDate, .dateAdded: ("Oldest First", "Newest First")
            case .rating: ("Lowest First", "Highest First")
            }
        }
    }

    var field: Field
    var ascending: Bool

    static let `default` = LibrarySort(field: .title, ascending: true)
    static let newestAdded = LibrarySort(field: .dateAdded, ascending: false)

    /// Switching field resets the order to that field's natural direction.
    func with(field: Field) -> LibrarySort {
        LibrarySort(field: field, ascending: field.defaultAscending)
    }

    /// The `sort` query value, e.g. `titleSort:asc`.
    var plexValue: String { "\(field.plexKey):\(ascending ? "asc" : "desc")" }

    /// Stored in UserDefaults as `field:asc` / `field:desc`.
    var storageValue: String { "\(field.rawValue):\(ascending ? "asc" : "desc")" }

    init(field: Field, ascending: Bool) {
        self.field = field
        self.ascending = ascending
    }

    init?(storageValue: String) {
        let parts = storageValue.split(separator: ":")
        guard parts.count == 2, let field = Field(rawValue: String(parts[0])),
              parts[1] == "asc" || parts[1] == "desc" else { return nil }
        self.init(field: field, ascending: parts[1] == "asc")
    }
}
