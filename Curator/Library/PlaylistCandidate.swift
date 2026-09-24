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

    var id: String { ratingKey }

    init(ratingKey: String, title: String) {
        self.ratingKey = ratingKey
        self.title = title
    }

    init(_ item: PlexItem) {
        self.init(ratingKey: item.ratingKey, title: item.displayTitle)
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .curatorItem)
    }
}
