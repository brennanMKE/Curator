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

struct NewBadgeTests {
    private func item(addedAt: Date) throws -> PlexItem {
        let json = #"{"ratingKey":"1","type":"movie","title":"t","addedAt":\#(addedAt.timeIntervalSince1970)}"#
        return try JSONDecoder().decode(PlexItem.self, from: Data(json.utf8))
    }

    let now = Date(timeIntervalSince1970: 1_790_114_400)

    @Test func newForThreeHours() throws {
        #expect(RecentStore.isNew(try item(addedAt: now - 60), now: now))
        #expect(RecentStore.isNew(try item(addedAt: now - 3 * 3600 + 60), now: now))
        #expect(!RecentStore.isNew(try item(addedAt: now - 3 * 3600 - 60), now: now))
    }

    @Test func noDateIsNotNew() throws {
        let json = #"{"ratingKey":"1","type":"movie","title":"t"}"#
        let undated = try JSONDecoder().decode(PlexItem.self, from: Data(json.utf8))
        #expect(!RecentStore.isNew(undated, now: now))
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
