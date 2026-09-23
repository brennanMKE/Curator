import Foundation

nonisolated enum Format {
    /// 7922998 ms → "2h 12m"
    static func runtime(milliseconds: Int) -> String {
        let minutes = Int((Double(milliseconds) / 60_000).rounded())
        let hours = minutes / 60
        if hours == 0 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h \(minutes % 60)m"
    }

    static func fileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// "SD · HEVC · AAC 2.0"
    static func mediaSummary(_ media: PlexMedia) -> String {
        var parts: [String] = []
        if let resolution = media.videoResolution {
            let label = switch resolution.lowercased() {
            case "sd": "SD"
            case "4k": "4K"
            case let value where Int(value) != nil: "\(value)p"
            default: resolution.uppercased()
            }
            parts.append(label)
        }
        if let codec = media.videoCodec { parts.append(codec.uppercased()) }
        if let codec = media.audioCodec {
            let channels = media.audioChannels.map { channelLayout($0) }
            parts.append([codec.uppercased(), channels].compactMap(\.self).joined(separator: " "))
        }
        return parts.joined(separator: " · ")
    }

    private static func channelLayout(_ channels: Int) -> String {
        switch channels {
        case 1: "1.0"
        case 2: "2.0"
        case 6: "5.1"
        case 8: "7.1"
        default: "\(channels)ch"
        }
    }

    static func relative(_ date: Date, to now: Date = .now) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
