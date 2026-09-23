import Foundation
import Testing
@testable import Curator

struct RecentGroupTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    /// 2026-09-22 15:00 Pacific
    let now = Date(timeIntervalSince1970: 1790114400)

    @Test func groups() {
        let hour: TimeInterval = 3600
        #expect(RecentGroup.group(for: now - hour, now: now, calendar: calendar) == .today)
        #expect(RecentGroup.group(for: now - 20 * hour, now: now, calendar: calendar) == .yesterday)
        #expect(RecentGroup.group(for: now - 4 * 24 * hour, now: now, calendar: calendar) == .lastWeek)
        #expect(RecentGroup.group(for: now - 30 * 24 * hour, now: now, calendar: calendar) == .earlier)
    }
}

@MainActor
struct RecentStoreTests {
    private func item(_ key: String, addedAt: TimeInterval) throws -> PlexItem {
        let json = #"{"ratingKey":"\#(key)","type":"movie","title":"t","addedAt":\#(addedAt)}"#
        return try JSONDecoder().decode(PlexItem.self, from: Data(json.utf8))
    }

    private func freshDefaults() -> UserDefaults {
        let name = "CuratorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func nothingIsNewWithoutABaseline() throws {
        let store = RecentStore(defaults: freshDefaults())
        #expect(store.isNew(try item("1", addedAt: 1_790_000_000)) == false)
    }

    @Test func lastSessionBecomesTheBaseline() throws {
        let defaults = freshDefaults()
        defaults.set(1_790_000_000.0, forKey: "recentSeenBaseline")
        defaults.set(1_790_100_000.0, forKey: "recentNextBaseline")

        let store = RecentStore(defaults: defaults)
        #expect(store.isNew(try item("old", addedAt: 1_790_050_000)) == false)
        #expect(store.isNew(try item("new", addedAt: 1_790_200_000)))
        #expect(defaults.object(forKey: "recentNextBaseline") == nil)
    }
}

struct FormatTests {
    @Test func runtime() {
        #expect(Format.runtime(milliseconds: 7_922_998) == "2h 12m")
        #expect(Format.runtime(milliseconds: 2_700_000) == "45m")
        #expect(Format.runtime(milliseconds: 7_200_000) == "2h")
    }

    @Test func mediaSummary() throws {
        let json = #"{"videoResolution":"sd","videoCodec":"hevc","audioCodec":"aac","audioChannels":2}"#
        let media = try JSONDecoder().decode(PlexMedia.self, from: Data(json.utf8))
        #expect(Format.mediaSummary(media) == "SD · HEVC · AAC 2.0")
    }

    @Test func justNow() {
        let now = Date()
        #expect(Format.relative(now - 10, to: now) == "just now")
    }
}
