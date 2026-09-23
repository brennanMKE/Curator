import Foundation
import Testing
@testable import Curator

struct PlexServerURLTests {
    @Test(arguments: [
        ("joe", "http://joe:32400"),
        ("  joe\n", "http://joe:32400"),
        ("joe:32400", "http://joe:32400"),
        ("192.0.2.10", "http://192.0.2.10:32400"),
        ("http://joe:32400/", "http://joe:32400"),
        ("HTTP://joe:32400", "http://joe:32400"),
        ("https://plex.example.com", "https://plex.example.com"),
        ("http://joe:32400/web/?x=1#y", "http://joe:32400/web"),
    ])
    func normalizes(input: String, expected: String) {
        #expect(PlexServerURL.normalize(input)?.absoluteString == expected)
    }

    @Test(arguments: ["", "   ", "http://", "ftp://joe", "http://:32400"])
    func rejects(input: String) {
        #expect(PlexServerURL.normalize(input) == nil)
    }
}
