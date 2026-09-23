import Foundation
import Testing
@testable import Curator

struct TMDBClientTests {
    @Test func blankIsNoCredential() {
        #expect(TMDBClient.Credential("  \n") == nil)
    }

    @Test func shortKeyIsV3() {
        #expect(TMDBClient.Credential(" 0123456789abcdef \n") == .apiKey("0123456789abcdef"))
    }

    @Test func jwtIsBearer() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJ4In0.c2lnbmF0dXJl"
        #expect(TMDBClient.Credential(jwt) == .bearer(jwt))
    }

    @Test func apiKeyGoesInQuery() {
        let request = TMDBClient(credential: .apiKey("abc")).request("authentication")
        #expect(request.url?.absoluteString == "https://api.themoviedb.org/3/authentication?api_key=abc")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func bearerGoesInHeader() {
        let request = TMDBClient(credential: .bearer("eyJ.a.b")).request("authentication")
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer eyJ.a.b")
    }
}
