import Foundation
import Testing
@testable import Curator

/// Payloads captured from joe (Plex Media Server 1.43.4), trimmed.
struct PlexDecodingTests {
    private func decode<T: Decodable & Sendable>(_ json: String, as _: T.Type) throws -> T {
        try JSONDecoder().decode(PlexEnvelope<T>.self, from: Data(json.utf8)).mediaContainer
    }

    @Test func serverInfo() throws {
        let info = try decode("""
            {"MediaContainer":{"size":0,"friendlyName":"brennan-mac-mini-m1","machineIdentifier":"19fa8d3068e821b3176b5930734c0eaf226cd5a2","version":"1.43.4.10903-e5521bd8c","claimed":true}}
            """, as: PlexServerInfo.self)
        #expect(info.friendlyName == "brennan-mac-mini-m1")
        #expect(info.shortVersion == "1.43.4")
    }

    @Test func sections() throws {
        let list = try decode("""
            {"MediaContainer":{"size":2,"Directory":[
              {"key":"4","type":"movie","title":"Movies","agent":"tv.plex.agents.movie","thumb":null},
              {"key":"2","type":"show","title":"TV Shows","agent":"tv.plex.agents.series"}
            ]}}
            """, as: PlexSectionList.self)
        #expect(list.sections.map(\.key) == ["4", "2"])
        #expect(list.sections.map(\.kind) == [.movie, .show])
    }

    @Test func sectionsWhenServerHasNone() throws {
        let list = try decode(#"{"MediaContainer":{"size":0}}"#, as: PlexSectionList.self)
        #expect(list.sections.isEmpty)
    }

    @Test func count() throws {
        let counts = try decode("""
            {"MediaContainer":{"size":0,"totalSize":54,"offset":0,"librarySectionID":4,"title1":"Movies"}}
            """, as: PlexCount.self)
        #expect(counts.totalSize == 54)
    }
}
