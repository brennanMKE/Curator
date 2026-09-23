import Foundation

nonisolated enum RecentGroup: String, CaseIterable, Sendable {
    case today = "Today"
    case yesterday = "Yesterday"
    case lastWeek = "Last 7 Days"
    case earlier = "Earlier"

    static func group(for date: Date, now: Date, calendar: Calendar = .current) -> RecentGroup {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return .yesterday }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)),
           date >= weekAgo { return .lastWeek }
        return .earlier
    }

    /// Splits items (already newest-first) into non-empty groups, in order.
    static func sections(_ items: [PlexItem], now: Date, calendar: Calendar = .current) -> [(group: RecentGroup, items: [PlexItem])] {
        let grouped = Dictionary(grouping: items) { item in
            item.addedAt.map { group(for: $0, now: now, calendar: calendar) } ?? .earlier
        }
        return allCases.compactMap { group in
            grouped[group].map { (group, $0) }
        }
    }
}
