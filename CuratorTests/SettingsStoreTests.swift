import Foundation
import Testing
@testable import Curator

struct EnvFileTests {
    @Test func parsesTheRepoFormat() {
        let file = EnvFile("""
            # Curator
            PLEX_URL=http://joe:32400
            export PLEX_TOKEN="abc123"
            TMDB_API_KEY='k'
            BROKEN LINE
            """)
        #expect(file["PLEX_URL"] == "http://joe:32400")
        #expect(file["PLEX_TOKEN"] == "abc123")
        #expect(file["TMDB_API_KEY"] == "k")
        #expect(file["MISSING"] == nil)
    }

    @Test func updatesInPlaceAndKeepsOtherLines() {
        var file = EnvFile("# keep\nPLEX_URL=http://a\nOTHER=1\n")
        file["PLEX_URL"] = "http://joe:32400"
        file["TMDB_API_KEY"] = "k"
        #expect(file.text == "# keep\nPLEX_URL=http://joe:32400\nOTHER=1\nTMDB_API_KEY=k\n")
    }

    @Test func emptyValueRemovesTheKey() {
        var file = EnvFile("PLEX_TOKEN=abc\n")
        file["PLEX_TOKEN"] = ""
        #expect(file.text == "")
    }

    @Test func blankValueFromTheExampleReadsAsEmpty() {
        #expect(EnvFile("TMDB_API_KEY=\n")["TMDB_API_KEY"] == "")
    }
}

@MainActor
struct SettingsStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "CuratorTests-\(UUID().uuidString)/.env")
    }

    @Test func defaultsWithoutAFile() {
        let store = SettingsStore(fileURL: tempURL())
        #expect(store.serverAddress == SettingsStore.defaultServerAddress)
        #expect(store.plexToken.isEmpty)
        #expect(store.tmdbClient == nil)
        #expect(!store.isPlexConfigured)
    }

    @Test func savesAndReloads() throws {
        let url = tempURL()
        let store = SettingsStore(fileURL: url)
        store.plexToken = " token\n"
        store.tmdbKey = "key"

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("PLEX_TOKEN=token"))
        #expect(text.contains("TMDB_API_KEY=key"))
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)

        let reloaded = SettingsStore(fileURL: url)
        #expect(reloaded.plexToken == "token")
        #expect(reloaded.isPlexConfigured)
    }

    @Test func importsOnlyCuratorKeys() {
        let store = SettingsStore(fileURL: tempURL())
        let imported = store.importValues(from: EnvFile("TMDB_API_KEY=abc\nPLEX_TOKEN=\nUNRELATED=x\n"))
        #expect(imported == ["TMDB_API_KEY"])
        #expect(store.tmdbKey == "abc")
        #expect(store.plexToken.isEmpty)
    }
}
