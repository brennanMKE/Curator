import os

nonisolated enum Log {
    static let subsystem = "co.sstools.Curator"
    static let plex = Logger(subsystem: subsystem, category: "plex")
    static let tmdb = Logger(subsystem: subsystem, category: "tmdb")
    static let settings = Logger(subsystem: subsystem, category: "settings")
}
