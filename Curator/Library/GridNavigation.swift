import Foundation

/// Arrow-key movement through a sectioned grid, where each section starts a new row.
nonisolated enum GridNavigation {
    enum Direction: Sendable {
        case left, right, up, down
    }

    struct Position: Equatable, Sendable {
        var section: Int
        var index: Int
    }

    /// The position after moving, or `nil` when there is nowhere to go.
    /// With no current position, any direction lands on the first item.
    static func move(from position: Position?, _ direction: Direction, counts: [Int], columns: Int) -> Position? {
        let columns = max(1, columns)
        guard let position else {
            return counts.firstIndex { $0 > 0 }.map { Position(section: $0, index: 0) }
        }
        let count = counts[position.section]
        let column = position.index % columns

        switch direction {
        case .left:
            if position.index > 0 { return Position(section: position.section, index: position.index - 1) }
            return previousSection(before: position.section, counts: counts).map { Position(section: $0, index: counts[$0] - 1) }

        case .right:
            if position.index + 1 < count { return Position(section: position.section, index: position.index + 1) }
            return nextSection(after: position.section, counts: counts).map { Position(section: $0, index: 0) }

        case .down:
            let lastRow = (count - 1) / columns
            if position.index / columns < lastRow {
                return Position(section: position.section, index: min(position.index + columns, count - 1))
            }
            return nextSection(after: position.section, counts: counts).map {
                Position(section: $0, index: min(column, counts[$0] - 1))
            }

        case .up:
            if position.index >= columns { return Position(section: position.section, index: position.index - columns) }
            return previousSection(before: position.section, counts: counts).map {
                let lastRowStart = (counts[$0] - 1) / columns * columns
                return Position(section: $0, index: min(lastRowStart + column, counts[$0] - 1))
            }
        }
    }

    /// How many columns `LazyVGrid`'s adaptive layout fits into `width`.
    static func columns(width: CGFloat, minimum: CGFloat, spacing: CGFloat) -> Int {
        max(1, Int(((width + spacing) / (minimum + spacing)).rounded(.down)))
    }

    private static func nextSection(after section: Int, counts: [Int]) -> Int? {
        counts.indices.first { $0 > section && counts[$0] > 0 }
    }

    private static func previousSection(before section: Int, counts: [Int]) -> Int? {
        counts.indices.last { $0 < section && counts[$0] > 0 }
    }
}
