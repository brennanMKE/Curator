import Foundation
import Testing
@testable import Curator

struct GridNavigationTests {
    typealias P = GridNavigation.Position

    /// Two sections: 6 items (rows of 4: 0-3, 4-5), then 3 items.
    let counts = [6, 3]

    private func move(_ from: P?, _ direction: GridNavigation.Direction, counts: [Int]? = nil) -> P? {
        GridNavigation.move(from: from, direction, counts: counts ?? self.counts, columns: 4)
    }

    @Test func startsAtFirstItem() {
        #expect(move(nil, .down) == P(section: 0, index: 0))
        #expect(move(nil, .right, counts: [0, 2]) == P(section: 1, index: 0))
        #expect(move(nil, .down, counts: [0, 0]) == nil)
    }

    @Test func leftAndRightFlowAcrossSections() {
        #expect(move(P(section: 0, index: 5), .right) == P(section: 1, index: 0))
        #expect(move(P(section: 1, index: 0), .left) == P(section: 0, index: 5))
        #expect(move(P(section: 0, index: 0), .left) == nil)
        #expect(move(P(section: 1, index: 2), .right) == nil)
    }

    @Test func downClampsIntoAShortLastRow() {
        #expect(move(P(section: 0, index: 1), .down) == P(section: 0, index: 5))
        #expect(move(P(section: 0, index: 3), .down) == P(section: 0, index: 5))
    }

    @Test func downFromLastRowEntersNextSectionInSameColumn() {
        #expect(move(P(section: 0, index: 5), .down) == P(section: 1, index: 1))
        #expect(move(P(section: 1, index: 2), .down) == nil)
    }

    @Test func upFromFirstRowEntersPreviousSectionsLastRow() {
        #expect(move(P(section: 1, index: 0), .up) == P(section: 0, index: 4))
        #expect(move(P(section: 1, index: 2), .up) == P(section: 0, index: 5))
        #expect(move(P(section: 0, index: 5), .up) == P(section: 0, index: 1))
        #expect(move(P(section: 0, index: 2), .up) == nil)
    }

    @Test func skipsEmptySections() {
        #expect(move(P(section: 0, index: 5), .right, counts: [6, 0, 2]) == P(section: 2, index: 0))
    }

    @Test func adaptiveColumnCount() {
        // 4 × 140 + 3 × 20 = 620
        #expect(GridNavigation.columns(width: 620, minimum: 140, spacing: 20) == 4)
        #expect(GridNavigation.columns(width: 619, minimum: 140, spacing: 20) == 3)
        #expect(GridNavigation.columns(width: 50, minimum: 140, spacing: 20) == 1)
    }
}
