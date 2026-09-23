import Foundation

nonisolated enum PlexServerURL {
    static let defaultPort = 32400

    /// Turns what someone types ("joe", "joe:32400", "http://joe:32400/") into a base URL.
    /// A bare host gets `http://` and Plex's default port; a full URL is taken as written,
    /// so a reverse proxy on 443 still works.
    static func normalize(_ input: String) -> URL? {
        var text = input.trimmed
        guard !text.isEmpty else { return nil }

        let hasScheme = text.contains("://")
        if !hasScheme { text = "http://" + text }

        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return nil }

        components.scheme = scheme
        if !hasScheme && components.port == nil { components.port = defaultPort }
        while components.path.hasSuffix("/") { components.path.removeLast() }
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
