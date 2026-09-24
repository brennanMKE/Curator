import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Curator's own drag type (declared in Info.plist), so only Curator accepts its drags.
    nonisolated static let curatorItem = UTType(exportedAs: "co.sstools.curator.item")
}

/// A title on its way into a playlist: dragged from a poster, or chosen from a context menu.
nonisolated struct PlaylistCandidate: Codable, Hashable, Identifiable, Sendable, Transferable {
    let ratingKey: String
    let title: String
    /// Set when the drag starts inside a playlist, so dropping it on another entry of that
    /// playlist moves this exact entry (a title can be in a playlist twice).
    var playlistItemID: String?

    var id: String { ratingKey }

    init(ratingKey: String, title: String, playlistItemID: String? = nil) {
        self.ratingKey = ratingKey
        self.title = title
        self.playlistItemID = playlistItemID
    }

    init(_ item: PlexItem) {
        self.init(ratingKey: item.ratingKey, title: item.displayTitle, playlistItemID: item.playlistItemID)
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .curatorItem)
    }
}
