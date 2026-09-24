import Foundation
import Testing
@testable import Curator

/// PlaylistStore against a stubbed Plex. Serialized: the stub's routes are shared.
extension StubbedNetworkTests {
    @MainActor
    @Suite
    struct PlaylistStoreTests {
        nonisolated static let machine = "MID"

        private func store(defaults: UserDefaults = freshDefaults()) -> PlaylistStore {
            let store = PlaylistStore(defaults: defaults)
            store.context = { PlaylistContext(client: Stub.context().client, machineIdentifier: Self.machine) }
            return store
        }

        private static func freshDefaults() -> UserDefaults {
            let name = "CuratorTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defaults.removePersistentDomain(forName: name)
            return defaults
        }

        private nonisolated static func playlistsJSON(_ items: [(id: String, title: String, added: Int)]) -> String {
            let metadata = items.map { #"{"ratingKey":"\#($0.id)","title":"\#($0.title)","leafCount":1,"addedAt":\#($0.added),"updatedAt":\#($0.added)}"# }
            return #"{"MediaContainer":{"size":\#(items.count),"Metadata":[\#(metadata.joined(separator: ","))]}}"#
        }

        private nonisolated static func entriesJSON(_ entries: [(key: String, entry: Int)]) -> String {
            let metadata = entries.map { #"{"ratingKey":"\#($0.key)","type":"movie","title":"T\#($0.key)","playlistItemID":\#($0.entry)}"# }
            return #"{"MediaContainer":{"size":\#(entries.count),"Metadata":[\#(metadata.joined(separator: ","))]}}"#
        }

        let dieHard = PlaylistCandidate(ratingKey: "493", title: "Die Hard")
        let dieHard2 = PlaylistCandidate(ratingKey: "499", title: "Die Hard 2")

        @Test func createSendsTheItemsURIAndReports() async throws {
            StubURLProtocol.route { request in
                request.httpMethod == "POST"
                    ? .init(json: Self.playlistsJSON([("531", "Die Hard Marathon", 1_790_000_000)]))
                    : .init(json: Self.playlistsJSON([("531", "Die Hard Marathon", 1_790_000_000)]))
            }
            let store = store()
            store.create(named: " Die Hard Marathon ", with: dieHard)
            #expect(await eventually { store.event != nil })
            #expect(store.event?.message == "Created Die Hard Marathon with Die Hard")
            #expect(store.recent.first?.title == "Die Hard Marathon")

            let post = try #require(StubURLProtocol.requests.first)
            let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: post, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            #expect(StubURLProtocol.calls.first == "POST /playlists")
            #expect(query["type"] == "video")
            #expect(query["title"] == "Die Hard Marathon")
            #expect(query["uri"] == "server://MID/com.plexapp.plugins.library/library/metadata/493")
        }

        @Test func duplicatesAreReportedNotAdded() async {
            StubURLProtocol.route { request in
                request.httpMethod == "PUT"
                    ? .init(json: #"{"MediaContainer":{"leafCountAdded":0,"leafCountRequested":1}}"#)
                    : .init(json: Self.playlistsJSON([("531", "Die Hard Marathon", 1)]))
            }
            let store = store()
            store.reload()
            #expect(await eventually { store.playlist("531") != nil })
            store.add(dieHard, to: store.playlist("531")!)
            #expect(await eventually { store.event != nil })
            #expect(store.event?.kind == .info)
            #expect(store.event?.message == "Die Hard is already in Die Hard Marathon")
            #expect(store.event?.undo == nil)
        }

        @Test func undoRemovesOnlyWhatWasAdded() async {
            StubURLProtocol.route { request in
                let path = request.url?.path() ?? ""
                switch (request.httpMethod ?? "GET", path) {
                case ("PUT", "/playlists/531/items"):
                    return .init(json: #"{"MediaContainer":{"leafCountAdded":1,"leafCountRequested":1}}"#)
                case ("GET", "/playlists/531/items"):
                    return .init(json: Self.entriesJSON([("493", 77), ("499", 78)]))
                default:
                    return .init(json: Self.playlistsJSON([("531", "Die Hard Marathon", 1)]))
                }
            }
            let store = store()
            store.reload()
            #expect(await eventually { store.playlist("531") != nil })
            store.add(dieHard2, to: store.playlist("531")!)
            #expect(await eventually { store.event?.kind == .success })
            #expect(store.event?.undo == .init(playlistID: "531", playlistItemIDs: ["78"]))

            store.undo()
            #expect(await eventually { StubURLProtocol.calls.contains("DELETE /playlists/531/items/78") })
            #expect(!StubURLProtocol.calls.contains("DELETE /playlists/531/items/77"))
        }

        @Test func recencyUsesCuratorActivityThenPlexDates() async {
            let defaults = Self.freshDefaults()
            // Curator changed "Old" most recently, though Plex says it was created first.
            defaults.set(["1": 1_800_000_000.0], forKey: "playlistActivity.\(Self.machine)")
            StubURLProtocol.route { _ in
                .init(json: Self.playlistsJSON([("1", "Old", 1_700_000_000), ("2", "Newer", 1_790_000_000), ("3", "Middle", 1_750_000_000)]))
            }
            let store = store(defaults: defaults)
            store.reload()
            #expect(await eventually { store.playlists.count == 3 })
            #expect(store.byRecency.map(\.title) == ["Old", "Newer", "Middle"])
            #expect(store.alphabetical.map(\.title) == ["Middle", "Newer", "Old"])
        }

        @Test func moveSendsTheRightNeighbour() async {
            StubURLProtocol.route { request in
                request.url?.path() == "/playlists/531/items" && request.httpMethod == "GET"
                    ? .init(json: Self.entriesJSON([("a", 1), ("b", 2), ("c", 3)]))
                    : .init(json: Self.playlistsJSON([("531", "P", 1)]))
            }
            let store = store()
            store.reload()
            #expect(await eventually { store.playlist("531") != nil })
            let playlist = store.playlist("531")!
            store.loadEntries(of: "531")
            #expect(await eventually { store.entries["531"]?.count == 3 })

            store.move(in: playlist, from: [2], to: 0)   // c to the top
            #expect(store.entries["531"]?.map(\.ratingKey) == ["c", "a", "b"])
            #expect(await eventually { StubURLProtocol.requests.contains { $0.path() == "/playlists/531/items/3/move" && $0.query == nil } })

            store.move(in: playlist, from: [1], to: 3)   // a to the end, after b
            #expect(store.entries["531"]?.map(\.ratingKey) == ["c", "b", "a"])
            #expect(await eventually { StubURLProtocol.requests.contains { $0.path() == "/playlists/531/items/1/move" && $0.query == "after=2" } })
        }
    }
}
