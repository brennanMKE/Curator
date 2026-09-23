import Foundation

/// Reads and writes `KEY=value` files in the same format as the repo's `.env`.
/// Comments, blank lines and unknown keys are preserved when a value changes.
nonisolated struct EnvFile: Equatable, Sendable {
    private(set) var lines: [String]

    init(_ text: String = "") {
        lines = text.isEmpty ? [] : text.components(separatedBy: .newlines)
        while lines.last?.isEmpty == true { lines.removeLast() }
    }

    init(contentsOf url: URL) throws {
        self.init(try String(contentsOf: url, encoding: .utf8))
    }

    var text: String { lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n" }

    subscript(key: String) -> String? {
        get {
            lines.lazy.compactMap(Self.parse).last { $0.key == key }?.value
        }
        set {
            let index = lines.lastIndex { Self.parse($0)?.key == key }
            guard let newValue, !newValue.isEmpty else {
                if let index { lines.remove(at: index) }
                return
            }
            let line = "\(key)=\(Self.quoteIfNeeded(newValue))"
            if let index { lines[index] = line } else { lines.append(line) }
        }
    }

    static func parse(_ line: String) -> (key: String, value: String)? {
        var text = line.trimmed
        guard !text.isEmpty, !text.hasPrefix("#") else { return nil }
        if text.hasPrefix("export ") { text = String(text.dropFirst(7)).trimmed }
        guard let equals = text.firstIndex(of: "=") else { return nil }
        let key = String(text[..<equals]).trimmed
        guard !key.isEmpty else { return nil }
        var value = String(text[text.index(after: equals)...]).trimmed
        if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
            value = String(value.dropFirst().dropLast())
        }
        return (key, value)
    }

    private static func quoteIfNeeded(_ value: String) -> String {
        value.contains(where: { $0.isWhitespace || $0 == "#" }) ? "\"\(value)\"" : value
    }
}
