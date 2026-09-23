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

    private func item(_ key: String, _ title: String, titleSort: String? = nil, rating: Double? = nil, released: String? = nil) throws -> PlexItem {
        var fields = [#""ratingKey":"\#(key)""#, #""type":"movie""#, #""title":"\#(title)""#]
        if let titleSort { fields.append(#""titleSort":"\#(titleSort)""#) }
        if let rating { fields.append(#""audienceRating":\#(rating)"#) }
        if let released { fields.append(#""originallyAvailableAt":"\#(released)""#) }
        return try JSONDecoder().decode(PlexItem.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    @Test func titleSortIgnoresLeadingArticlesLikePlex() throws {
        let items = [
            try item("1", "The Big Lebowski", titleSort: "Big Lebowski"),
            try item("2", "Army of Darkness"),
            try item("3", "The Adjustment Bureau", titleSort: "Adjustment Bureau"),
        ]
        #expect(LibrarySort.default.sorted(items).map(\.id) == ["3", "2", "1"])
        #expect(LibrarySort(field: .title, ascending: false).sorted(items).map(\.id) == ["1", "2", "3"])
    }

    @Test func missingValuesGoLastEitherWay() throws {
        let items = [
            try item("unrated", "A"),
            try item("low", "B", rating: 6.1),
            try item("high", "C", rating: 9.3),
        ]
        #expect(LibrarySort(field: .rating, ascending: false).sorted(items).map(\.id) == ["high", "low", "unrated"])
        #expect(LibrarySort(field: .rating, ascending: true).sorted(items).map(\.id) == ["low", "high", "unrated"])
    }

    @Test func releaseDateOrderAndStableTies() throws {
        let items = [
            try item("a", "A", released: "1996-03-22"),
            try item("b", "B", released: "1998-03-06"),
            try item("c", "C", released: "1996-03-22"),
        ]
        #expect(LibrarySort(field: .releaseDate, ascending: true).sorted(items).map(\.id) == ["a", "c", "b"])
        #expect(LibrarySort(field: .releaseDate, ascending: false).sorted(items).map(\.id) == ["b", "a", "c"])
    }
}
