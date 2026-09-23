import Foundation
import Testing
@testable import Curator

struct SearchResultsTests {
    /// `/hubs/search?query=coen` from joe, trimmed to the hubs that matter.
    static let hubJSON = """
        {"MediaContainer":{"size":3,"Hub":[
          {"type":"show","hubIdentifier":"show","size":0},
          {"type":"movie","hubIdentifier":"movie","size":2,"Metadata":[
            {"type":"movie","ratingKey":"167","title":"The Big Lebowski","year":1998,"reason":"director","reasonTitle":"Joel Coen","librarySectionID":4},
            {"type":"movie","ratingKey":"198","title":"Fargo","year":1996,"reason":"director","reasonTitle":"Joel Coen","librarySectionID":4}]},
          {"type":"director","hubIdentifier":"director","size":2,"Directory":[{"type":"tag","tag":"Joel Coen","tagType":4}]}
        ]}}
        """

    private func hubs() throws -> [PlexHub] {
        try JSONDecoder().decode(PlexEnvelope<PlexHubList>.self, from: Data(Self.hubJSON.utf8)).mediaContainer.hubs
    }

    private func movie(_ key: String, _ title: String) throws -> PlexItem {
        let json = #"{"ratingKey":"\#(key)","type":"movie","title":"\#(title)"}"#
        return try JSONDecoder().decode(PlexItem.self, from: Data(json.utf8))
    }

    @Test func decodesHubs() throws {
        let hubs = try hubs()
        #expect(hubs.map(\.type) == ["show", "movie", "director"])
        #expect(hubs[1].items.map(\.title) == ["The Big Lebowski", "Fargo"])
    }

    @Test func hubOnlyMatchesGoToOtherMatches() throws {
        let results = SearchResults.merge(query: "coen", titleMatches: [], hubs: try hubs())
        #expect(results.titleMatches.isEmpty)
        #expect(results.otherMatches.map(\.title) == ["The Big Lebowski", "Fargo"])
        #expect(SearchResults.reasonLabel(for: results.otherMatches[0]) == "Director: Joel Coen")
    }

    @Test func titleMatchesWinAndAreNotRepeated() throws {
        let fargo = try movie("198", "Fargo")
        let results = SearchResults.merge(query: "fargo", titleMatches: [[fargo], [fargo]], hubs: try hubs())
        #expect(results.titleMatches.map(\.id) == ["198"])
        #expect(results.otherMatches.map(\.id) == ["167"])
    }

    @Test func reasonLabels() throws {
        let actor = try JSONDecoder().decode(PlexItem.self, from: Data(#"{"ratingKey":"1","type":"movie","title":"x","reason":"actor","reasonTitle":"John Belushi"}"#.utf8))
        #expect(SearchResults.reasonLabel(for: actor) == "Cast: John Belushi")
        #expect(SearchResults.reasonLabel(for: try movie("2", "y")) == "Similar title")
    }
}
