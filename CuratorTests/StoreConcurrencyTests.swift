import Foundation
import Testing
@testable import Curator

/// Regressions for requests racing each other: a late response must never overwrite
/// newer state, and typing must not fire duplicate searches.
@MainActor
@Suite(.serialized)
struct StoreConcurrencyTests {
    @Test func slowEarlierSearchCannotOverwriteLaterOne() async {
        // "army" answers slowly, "breakfast" quickly: the user's exact sequence.
        StubURLProtocol.route { request in
            if request.url?.path() == "/hubs/search" { return .init(json: Stub.noHubs) }
            switch Stub.query(request, "title") {
            case "army": return .init(delay: .milliseconds(800), json: Stub.items([("1", "Army of Darkness")]))
            default: return .init(json: Stub.items([]))
            }
        }
        let search = SearchStore()
        search.context = { Stub.context() }

        search.query = "army"
        try? await Task.sleep(for: .milliseconds(400))   // debounce passed; "army" in flight
        search.query = "breakfast"

        #expect(await eventually { search.currentResults != nil })
        try? await Task.sleep(for: .milliseconds(700))   // let the slow "army" response land
        #expect(search.results?.query == "breakfast")
        #expect(search.results?.isEmpty == true)
        #expect(!search.isSearching)
    }

    @Test func typingSearchesOnceForTheSettledText() async {
        StubURLProtocol.route { request in
            request.url?.path() == "/hubs/search" ? .init(json: Stub.noHubs) : .init(json: Stub.items([]))
        }
        let search = SearchStore()
        search.context = { Stub.context() }

        for text in ["b", "br", "bre", "brea", "break", "breakfast"] {
            search.query = text
            try? await Task.sleep(for: .milliseconds(30))
        }
        #expect(await eventually { search.currentResults?.query == "breakfast" })

        let titleSearches = StubURLProtocol.requests.compactMap { url in
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "title" }?.value
        }
        #expect(titleSearches == ["breakfast"])
    }

    @Test func clearingTheFieldStopsSearching() async {
        StubURLProtocol.route { _ in .init(delay: .milliseconds(500), json: Stub.items([])) }
        let search = SearchStore()
        search.context = { Stub.context() }

        search.query = "army"
        #expect(search.isSearching)
        search.query = ""
        #expect(!search.isSearching)
        try? await Task.sleep(for: .milliseconds(900))
        #expect(search.results == nil)
    }

    @Test func reloadSupersedesAnInFlightBrowseLoad() async {
        var calls = 0
        StubURLProtocol.route { _ in
            calls += 1
            return calls == 1
                ? .init(delay: .milliseconds(600), json: Stub.items([("old", "Stale")]))
                : .init(json: Stub.items([("1", "Fargo"), ("2", "Hackers")]))
        }
        let store = BrowseStore(section: Stub.movies)
        store.context = { Stub.context() }

        store.loadIfNeeded()
        try? await Task.sleep(for: .milliseconds(100))
        store.reload()

        #expect(await eventually { store.hasLoaded })
        try? await Task.sleep(for: .milliseconds(700))
        #expect(store.items.map(\.title) == ["Fargo", "Hackers"])
        #expect(!store.isLoading)
    }

    @Test func changingTheSortReloadsInThatOrder() async {
        StubURLProtocol.route { request in
            Stub.query(request, "sort") == "originallyAvailableAt:desc"
                ? .init(json: Stub.items([("2", "Newer"), ("1", "Older")]))
                : .init(json: Stub.items([("1", "Older"), ("2", "Newer")]))
        }
        let store = BrowseStore(section: Stub.movies)
        store.context = { Stub.context() }
        store.loadIfNeeded()
        #expect(await eventually { store.hasLoaded })
        #expect(store.items.map(\.title) == ["Older", "Newer"])

        store.setSort(LibrarySort(field: .releaseDate, ascending: false))
        #expect(await eventually { store.items.first?.title == "Newer" })
        #expect(StubURLProtocol.requests.compactMap { Stub.query(URLRequest(url: $0), "sort") }.last == "originallyAvailableAt:desc")
    }

    @Test func detailsLandOnTheirOwnItem() async {
        StubURLProtocol.route { request in
            let key = request.url?.lastPathComponent ?? ""
            let delay: Duration = key == "1" ? .milliseconds(400) : .zero
            return .init(delay: delay, json: Stub.items([(key, "Item \(key)")]))
        }
        let details = ItemDetailStore()
        details.context = { Stub.context() }

        details.load("1")
        details.load("2")
        #expect(await eventually { details.detail(for: "1") != nil && details.detail(for: "2") != nil })
        #expect(details.detail(for: "1")?.title == "Item 1")
        #expect(details.detail(for: "2")?.title == "Item 2")
    }

    @Test func searchWaitsForAConnection() async {
        let search = SearchStore()
        search.query = "army"
        #expect(await eventually { !search.isSearching })
        #expect(search.results == nil)
    }
}
