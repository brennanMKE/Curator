import Foundation
import Testing
@testable import Curator

/// Shapes captured from joe (Plex Media Server 1.43.4), trimmed.
struct PlexItemTests {
    static let movieJSON = """
        {"MediaContainer":{"size":1,"totalSize":55,"Metadata":[{
          "ratingKey":"448","type":"movie","title":"The Equalizer","year":2014,"contentRating":"R",
          "summary":"Robert McCall…","audienceRating":7.7,"tagline":"What do you see when you look at me?",
          "thumb":"/library/metadata/448/thumb/1790140674","art":"/library/metadata/448/art/1790140674",
          "duration":7922998,"addedAt":1790140674,"hasPremiumExtras":"1",
          "Media":[{"id":996,"width":720,"height":362,"audioChannels":2,"audioCodec":"aac","videoCodec":"hevc",
            "videoResolution":"sd","container":"mp4",
            "Part":[{"id":996,"file":"/Volumes/Media/Media/Movies/The Equalizer (2014) {tmdb-156022}/The Equalizer (2014).mp4","size":481872515}]}],
          "Guid":[{"id":"imdb://tt0455944"},{"id":"tmdb://156022"},{"id":"tvdb://136"}],
          "Genre":[{"tag":"Thriller"},{"tag":"Action"}],
          "Director":[{"tag":"Antoine Fuqua"}],
          "Role":[{"tag":"Denzel Washington"},{"tag":"Marton Csokas"}]
        }]}}
        """

    @Test func decodesMovie() throws {
        let list = try JSONDecoder().decode(PlexEnvelope<PlexItemList>.self, from: Data(Self.movieJSON.utf8)).mediaContainer
        #expect(list.totalSize == 55)
        let movie = try #require(list.items.first)
        #expect(movie.kind == .movie)
        #expect(movie.tmdbID == 156022)
        #expect(movie.addedAt == Date(timeIntervalSince1970: 1790140674))
        #expect(movie.genres == ["Thriller", "Action"])
        #expect(movie.directors == ["Antoine Fuqua"])
        #expect(movie.cast.first == "Denzel Washington")
        #expect(movie.filePath?.hasSuffix("The Equalizer (2014).mp4") == true)
        #expect(movie.media.first?.parts.first?.size == 481872515)
        #expect(movie.displaySubtitle == "2014")
        #expect(movie.posterPath == "/library/metadata/448/thumb/1790140674")
    }

    @Test func decodesEmptyListing() throws {
        let json = #"{"MediaContainer":{"size":0,"totalSize":0}}"#
        let list = try JSONDecoder().decode(PlexEnvelope<PlexItemList>.self, from: Data(json.utf8)).mediaContainer
        #expect(list.items.isEmpty)
    }

    @Test func episodeUsesShowTitleAndPoster() throws {
        let json = """
            {"MediaContainer":{"size":1,"Metadata":[{"ratingKey":"9","type":"episode","title":"Pilot",
              "grandparentTitle":"Breaking Bad","parentIndex":1,"index":1,
              "thumb":"/library/metadata/9/thumb/1","grandparentThumb":"/library/metadata/7/thumb/1"}]}}
            """
        let episode = try #require(JSONDecoder().decode(PlexEnvelope<PlexItemList>.self, from: Data(json.utf8)).mediaContainer.items.first)
        #expect(episode.displayTitle == "Breaking Bad")
        #expect(episode.displaySubtitle == "S1E1 · Pilot")
        #expect(episode.posterPath == "/library/metadata/7/thumb/1")
    }

    @Test func noTMDBGuid() throws {
        let json = #"{"MediaContainer":{"Metadata":[{"ratingKey":"1","type":"movie","title":"Knowing","Guid":[{"id":"imdb://tt0448011"}]}]}}"#
        let item = try #require(JSONDecoder().decode(PlexEnvelope<PlexItemList>.self, from: Data(json.utf8)).mediaContainer.items.first)
        #expect(item.tmdbID == nil)
    }
}
