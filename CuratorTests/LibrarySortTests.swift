import Foundation
import Testing
@testable import Curator

struct LibrarySortTests {
    @Test func plexValues() {
        #expect(LibrarySort.default.plexValue == "titleSort:asc")
        #expect(LibrarySort.newestAdded.plexValue == "addedAt:desc")
        #expect(LibrarySort(field: .releaseDate, ascending: true).plexValue == "originallyAvailableAt:asc")
        #expect(LibrarySort(field: .rating, ascending: false).plexValue == "audienceRating:desc")
    }

    @Test func switchingFieldUsesItsNaturalOrder() {
        let byTitle = LibrarySort(field: .title, ascending: false)
        #expect(byTitle.with(field: .releaseDate) == LibrarySort(field: .releaseDate, ascending: false))
        #expect(byTitle.with(field: .title) == LibrarySort(field: .title, ascending: true))
        #expect(byTitle.with(field: .rating).ascending == false)
    }

    @Test(arguments: LibrarySort.Field.allCases)
    func storageRoundTrips(field: LibrarySort.Field) {
        for ascending in [true, false] {
            let sort = LibrarySort(field: field, ascending: ascending)
            #expect(LibrarySort(storageValue: sort.storageValue) == sort)
        }
    }

    @Test(arguments: ["", "title", "title:up", "year:asc", "title:asc:x"])
    func rejectsBadStoredValues(value: String) {
        #expect(LibrarySort(storageValue: value) == nil)
    }

    @Test func requestEncodesTheSort() {
        let client = PlexClient(baseURL: URL(string: "http://joe:32400")!, token: "t")
        let request = client.request("/library/sections/4/all", query: [URLQueryItem(name: "sort", value: LibrarySort(field: .releaseDate, ascending: false).plexValue)])
        #expect(request.url?.query(percentEncoded: true) == "sort=originallyAvailableAt%3Adesc")
    }

    @Test func releaseDateIsACalendarDay() throws {
        let json = #"{"ratingKey":"1","type":"movie","title":"The Blues Brothers","originallyAvailableAt":"1980-06-16"}"#
        let item = try JSONDecoder().decode(PlexItem.self, from: Data(json.utf8))
        let date = try #require(item.releaseDate)
        #expect(Format.releaseDate(date).contains("1980"))
        #expect(Format.releaseDate(date).contains("16"))
    }
}
