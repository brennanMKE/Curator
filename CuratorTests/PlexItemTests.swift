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

    @Test func decodesExtras() throws {
        let json = """
            {"MediaContainer":{"size":2,"Metadata":[
              {"ratingKey":"901","type":"clip","subtype":"behindTheScenes","extraType":5,"title":"Making McCall","duration":612000},
              {"ratingKey":"902","type":"clip","title":"Untitled"}
            ]}}
            """
        let extras = try JSONDecoder().decode(PlexEnvelope<PlexItemList>.self, from: Data(json.utf8)).mediaContainer.items
        #expect(extras.map(\.extraLabel) == ["Behind the Scenes", "Extra"])
        #expect(extras.first?.subtype == "behindTheScenes")
        #expect(extras.first?.duration == 612000)
    }

    /// `/library/metadata/883/extras` from joe after importing bonus features, trimmed to two.
    static let extrasJSON = #"""
        {"MediaContainer": {"size": 2, "identifier": "com.plexapp.plugins.library", "mediaTagPrefix": "/system/bundle/media/flags/", "mediaTagVersion": 1789203812, "Metadata": [{"ratingKey": "895", "key": "/library/metadata/895", "guid": "file:///Volumes/Media/Media/Movies/The%20Lord%20of%20the%20Rings-%20The%20Fellowship%20of%20the%20Ring%20(2001)%20{tmdb-120}/Trailers/The%20Two%20Towers%20Preview.mp4", "type": "clip", "title": "The Two Towers Preview", "titleSort": "Two Towers Preview", "summary": "", "index": 1, "thumb": "/library/metadata/895/thumb/1791092149", "primaryGuid": "plex://movie/5d7768248a7581001f12bc70", "art": "/library/metadata/883/art/1791092149", "subtype": "trailer", "duration": 642758, "addedAt": 1791092149, "updatedAt": 1791092149, "extraType": 1, "Media": [{"id": 1996, "duration": 642758, "bitrate": 1311, "width": 710, "height": 480, "aspectRatio": 1.78, "audioChannels": 2, "audioCodec": "aac", "videoCodec": "hevc", "videoResolution": "480", "container": "mp4", "optimizedForStreaming": 0, "audioProfile": "lc", "has64bitOffsets": false, "videoProfile": "main", "Part": [{"id": 1996, "key": "/library/parts/1996/0/file.mp4", "duration": 642758, "file": "/Volumes/Media/Media/Movies/The Lord of the Rings- The Fellowship of the Ring (2001) {tmdb-120}/Trailers/The Two Towers Preview.mp4", "size": 105320432, "audioProfile": "lc", "container": "mp4", "has64bitOffsets": false, "optimizedForStreaming": false, "videoProfile": "main", "Stream": [{"id": 4117, "streamType": 1, "default": true, "codec": "hevc", "index": 0, "bitrate": 1139, "anamorphic": true, "bitDepth": 8, "chromaLocation": "left", "chromaSubsampling": "4:2:0", "codecID": "hvc1", "codedHeight": 480, "codedWidth": 712, "colorPrimaries": "smpte170m", "colorRange": "tv", "colorSpace": "smpte170m", "colorTrc": "bt709", "frameRate": 28.248, "height": 480, "level": 90, "pixelAspectRatio": "32:27", "profile": "main", "refFrames": 1, "streamIdentifier": "1", "width": 710, "displayTitle": "480p", "extendedDisplayTitle": "480p (HEVC Main)"}, {"id": 4118, "streamType": 2, "selected": true, "default": true, "codec": "aac", "index": 1, "channels": 2, "bitrate": 163, "language": "English", "languageTag": "en", "languageCode": "eng", "audioChannelLayout": "stereo", "profile": "lc", "samplingRate": 48000, "streamIdentifier": "2", "displayTitle": "English (AAC Stereo)", "extendedDisplayTitle": "English (AAC Stereo)"}]}]}], "Image": [{"alt": "The Two Towers Preview", "type": "coverPoster", "url": "/library/metadata/895/thumb/1791092149"}]}, {"ratingKey": "896", "key": "/library/metadata/896", "guid": "file:///Volumes/Media/Media/Movies/The%20Lord%20of%20the%20Rings-%20The%20Fellowship%20of%20the%20Ring%20(2001)%20{tmdb-120}/Behind%20The%20Scenes/A%20Passage%20to%20Middle-earth.mp4", "type": "clip", "title": "A Passage to Middle-earth", "titleSort": "Passage to Middle-earth", "summary": "", "index": 2, "thumb": "/library/metadata/896/thumb/1791092149", "art": "/library/metadata/883/art/1791092149", "subtype": "behindTheScenes", "duration": 2499030, "addedAt": 1791092149, "updatedAt": 1791092149, "chapterSource": "media", "extraType": 5, "Media": [{"id": 1997, "duration": 2499030, "bitrate": 1155, "width": 702, "height": 480, "aspectRatio": 1.33, "audioChannels": 2, "audioCodec": "aac", "videoCodec": "hevc", "videoResolution": "480", "container": "mp4", "videoFrameRate": "NTSC", "optimizedForStreaming": 0, "audioProfile": "lc", "has64bitOffsets": false, "videoProfile": "main", "Part": [{"id": 1997, "key": "/library/parts/1997/0/file.mp4", "duration": 2499030, "file": "/Volumes/Media/Media/Movies/The Lord of the Rings- The Fellowship of the Ring (2001) {tmdb-120}/Behind The Scenes/A Passage to Middle-earth.mp4", "size": 360926962, "audioProfile": "lc", "container": "mp4", "has64bitOffsets": false, "optimizedForStreaming": false, "videoProfile": "main", "Stream": [{"id": 4119, "streamType": 1, "default": true, "codec": "hevc", "index": 0, "bitrate": 982, "anamorphic": true, "bitDepth": 8, "chromaLocation": "left", "chromaSubsampling": "4:2:0", "codecID": "hvc1", "codedHeight": 480, "codedWidth": 704, "colorPrimaries": "smpte170m", "colorRange": "tv", "colorSpace": "smpte170m", "colorTrc": "bt709", "frameRate": 29.97, "height": 480, "level": 90, "pixelAspectRatio": "8:9", "profile": "main", "refFrames": 1, "streamIdentifier": "1", "width": 702, "displayTitle": "480p", "extendedDisplayTitle": "480p (HEVC Main)"}, {"id": 4120, "streamType": 2, "selected": true, "default": true, "codec": "aac", "index": 1, "channels": 2, "bitrate": 165, "language": "English", "languageTag": "en", "languageCode": "eng", "audioChannelLayout": "stereo", "profile": "lc", "samplingRate": 48000, "streamIdentifier": "2", "displayTitle": "English (AAC Stereo)", "extendedDisplayTitle": "English (AAC Stereo)"}]}]}], "Image": [{"alt": "A Passage to Middle-earth", "type": "coverPoster", "url": "/library/metadata/896/thumb/1791092149"}]}]}}
        """#

    @Test func decodesCapturedExtras() throws {
        let extras = try JSONDecoder().decode(PlexEnvelope<PlexItemList>.self, from: Data(Self.extrasJSON.utf8)).mediaContainer.items
        #expect(extras.map(\.extraLabel) == ["Trailer", "Behind the Scenes"])
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
