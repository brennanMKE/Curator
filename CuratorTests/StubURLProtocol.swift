import Foundation
import Testing
@testable import Curator

/// Every suite that uses StubURLProtocol nests in here: its routes are shared, so these suites
/// must not run at the same time as each other.
@Suite(.serialized)
enum StubbedNetworkTests {}

/// Serves canned Plex responses with per-request delays, and records every request.
/// Tests using it must be serialized: the routes are shared.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Route {
        var delay: Duration = .zero
        var json: String
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var router: (URLRequest) -> Route? = { _ in nil }
    nonisolated(unsafe) private static var log: [URL] = []
    nonisolated(unsafe) private static var methodLog: [String] = []

    static func route(_ router: @escaping (URLRequest) -> Route?) {
        lock.withLock {
            self.router = router
            log = []
            methodLog = []
        }
    }

    static var requests: [URL] { lock.withLock { log } }
    /// "METHOD /path" for each request, in order.
    static var calls: [String] { lock.withLock { zip(methodLog, log).map { "\($0) \($1.path())" } } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private var cancelled = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let route = Self.lock.withLock {
            if let url = request.url {
                Self.log.append(url)
                Self.methodLog.append(request.httpMethod ?? "GET")
            }
            return Self.router(request)
        }
        let seconds = route.map { Double($0.delay.components.attoseconds) / 1e18 + Double($0.delay.components.seconds) } ?? 0
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [self] in
            guard !cancelled else { return }
            guard let route, let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
                return
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(route.json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        cancelled = true
    }
}

enum Stub {
    static let movies = PlexSection.stub(key: "4", type: "movie", title: "Movies")

    static func context() -> PlexContext {
        PlexContext(
            client: PlexClient(baseURL: URL(string: "http://joe:32400")!, token: "t", session: StubURLProtocol.session()),
            sections: [movies]
        )
    }

    static func items(_ items: [(key: String, title: String)], total: Int? = nil) -> String {
        let metadata = items.map { #"{"ratingKey":"\#($0.key)","type":"movie","title":"\#($0.title)"}"# }.joined(separator: ",")
        return #"{"MediaContainer":{"size":\#(items.count),"totalSize":\#(total ?? items.count),"Metadata":[\#(metadata)]}}"#
    }

    static let noHubs = #"{"MediaContainer":{"size":0,"Hub":[]}}"#

    static func query(_ request: URLRequest, _ name: String) -> String? {
        request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == name }?.value
    }
}

extension PlexSection {
    static func stub(key: String, type: String, title: String) -> PlexSection {
        let json = #"{"key":"\#(key)","type":"\#(type)","title":"\#(title)"}"#
        return try! JSONDecoder().decode(PlexSection.self, from: Data(json.utf8))
    }
}

extension PlexGenre {
    static func stub(key: String, title: String) -> PlexGenre {
        try! JSONDecoder().decode(PlexGenre.self, from: Data(#"{"key":"\#(key)","title":"\#(title)"}"#.utf8))
    }
}

/// Polls until `condition` holds or the timeout passes.
@MainActor
func eventually(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}
