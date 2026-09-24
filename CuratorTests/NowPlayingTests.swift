import Foundation
import Testing
@testable import Curator

struct NowPlayingTests {
    /// Trimmed from joe's /status/sessions: a movie paused on an Apple TV, and an episode
    /// playing in a browser.
    static let sessionsJSON = #"""
    {"MediaContainer":{"size":2,"Metadata":[
      {"ratingKey":"493","type":"movie","title":"Die Hard","viewOffset":3112110,
       "Player":{"title":"Apple TV","product":"Plex for Apple TV","state":"paused","local":true}},
      {"ratingKey":"901","grandparentRatingKey":"900","type":"episode","title":"Pilot",
       "Player":{"product":"Plex Web","state":"playing"}}
    ]}}
    """#

    static func sessions(_ json: String = sessionsJSON) throws -> [PlexSession] {
        try JSONDecoder().decode(PlexEnvelope<PlexSessionList>.self, from: Data(json.utf8)).mediaContainer.sessions
    }

    @Test func decodesSessions() throws {
        let sessions = try Self.sessions()
        #expect(sessions.map(\.ratingKey) == ["493", "901"])
        #expect(sessions[0].player == .init(title: "Apple TV", product: "Plex for Apple TV", state: "paused"))
        #expect(sessions[1].grandparentRatingKey == "900")
    }

    @Test func nothingPlayingDecodesEmpty() throws {
        #expect(try Self.sessions(#"{"MediaContainer":{"size":0}}"#).isEmpty)
    }

    @Test func indexesMoviesEpisodesAndTheirShows() throws {
        let index = NowPlayingStore.index(try Self.sessions())
        #expect(index["493"] == NowPlaying(state: .paused, player: "Apple TV"))
        #expect(index["901"] == NowPlaying(state: .playing, player: "Plex Web"))
        #expect(index["900"] == NowPlaying(state: .playing, player: "Plex Web"))
        #expect(index["493"]?.description == "Paused on Apple TV")
    }

    @Test func playingBeatsPausedForTheSameTitle() throws {
        let json = #"""
        {"MediaContainer":{"Metadata":[
          {"ratingKey":"493","Player":{"title":"Mac","state":"playing"}},
          {"ratingKey":"493","Player":{"title":"Apple TV","state":"paused"}}
        ]}}
        """#
        #expect(NowPlayingStore.index(try Self.sessions(json))["493"] == NowPlaying(state: .playing, player: "Mac"))
    }
}
