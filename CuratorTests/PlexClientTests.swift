import Foundation
import Testing
@testable import Curator

struct PlexClientTests {
    let client = PlexClient(baseURL: URL(string: "http://joe:32400")!, token: "secret")

    @Test func sendsTokenAndAcceptsJSON() {
        let request = client.request("/library/sections")
        #expect(request.url?.absoluteString == "http://joe:32400/library/sections")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "secret")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.url?.query == nil, "the token belongs in a header, not the URL")
    }

    @Test func pagingSetsBothHeaders() {
        let request = client.request("/library/sections/4/all", page: .init(start: 50, size: 25))
        #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Start") == "50")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Size") == "25")
    }

    @Test func noPagingHeadersByDefault() {
        let request = client.request("/library/sections/4/all")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Start") == nil)
        #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Size") == nil)
    }

    @Test func rootPath() {
        #expect(client.request("/").url?.absoluteString == "http://joe:32400/")
    }

    @Test func queryIsStrictlyEncoded() {
        let request = client.request("/library/sections/4/all", query: [
            URLQueryItem(name: "sort", value: "addedAt:desc"),
            URLQueryItem(name: "title", value: "cowboys & aliens"),
        ])
        #expect(request.url?.query(percentEncoded: true) == "sort=addedAt%3Adesc&title=cowboys%20%26%20aliens")
    }

    @Test func imageRequestEncodesThePath() {
        let request = client.imageRequest(path: "/library/metadata/446/thumb/1790136490", width: 342, height: 513)
        #expect(request.url?.path() == "/photo/:/transcode")
        #expect(request.url?.query(percentEncoded: true)?.contains("url=%2Flibrary%2Fmetadata%2F446%2Fthumb%2F1790136490") == true)
    }
}
