import XCTest
@testable import FlareStatusKit

final class IdleTourTests: XCTestCase {
    private func ids(_ prefix: String, _ count: Int) -> [String] { (1...count).map { "\(prefix)\($0)" } }

    func testStopsCoverEveryGroupAndItsLastRow() {
        // 13 tiles in 5 columns: rows start at a1, a6, a11.
        let stops = IdleTour.stops(leading: ["down-x", "down-y"], sections: [ids("a", 13), ids("b", 3), [], ids("c", 20)], columns: 5)
        XCTAssertEqual(stops, ["down-x", "a1", "a11", "b1", "c1", "c11", "c16"])
        // Stepping one row at a time visits every row.
        XCTAssertEqual(IdleTour.stops(leading: [], sections: [ids("a", 13)], columns: 5, rowsPerStep: 1), ["a1", "a6", "a11"])
        XCTAssertEqual(IdleTour.stops(leading: [], sections: [ids("a", 1)], columns: 1), ["a1"])
        XCTAssertEqual(IdleTour.stops(leading: [], sections: [], columns: 0), [])
    }

    func testEveryRowIsWithinOneStepOfAStop() {
        for count in 1...64 {
            for columns in 1...5 {
                let tiles = ids("t", count)
                let stops = Set(IdleTour.stops(leading: [], sections: [tiles], columns: columns))
                let rows = (count + columns - 1) / columns
                XCTAssertTrue(stops.contains(tiles[(rows - 1) * columns]), "last row missing for \(count) tiles in \(columns) columns")
                for row in 0..<rows {
                    let near = [row, row + 1].contains { $0 < rows && stops.contains(tiles[$0 * columns]) }
                    XCTAssertTrue(near, "row \(row) is never brought on screen for \(count) tiles in \(columns) columns")
                }
            }
        }
    }

    func testNextStopFollowsTheFocusAndLoops() {
        let order = ["down-x"] + ids("a", 13) + ids("b", 3)
        let stops = IdleTour.stops(leading: ["down-x"], sections: [ids("a", 13), ids("b", 3)], columns: 5)
        XCTAssertEqual(stops, ["down-x", "a1", "a11", "b1"])

        // Walking the tour from the top visits every stop and wraps.
        var focus: String? = nil
        var walked: [String] = []
        for _ in 0..<6 {
            focus = IdleTour.next(after: focus, stops: stops, order: order)
            walked.append(focus!)
        }
        XCTAssertEqual(walked, ["down-x", "a1", "a11", "b1", "down-x", "a1"])

        // It continues from wherever a person left the focus.
        XCTAssertEqual(IdleTour.next(after: "a3", stops: stops, order: order), "a11")
        XCTAssertEqual(IdleTour.next(after: "a12", stops: stops, order: order), "b1")
        XCTAssertEqual(IdleTour.next(after: "b2", stops: stops, order: order), "down-x")
        XCTAssertEqual(IdleTour.next(after: "gone", stops: stops, order: order), "down-x")
        XCTAssertNil(IdleTour.next(after: "a1", stops: [], order: order))
    }

    func testSampleWallOfSixtyFourHasAStopInEveryGroup() {
        let snapshot = SampleData.snapshot(.large, now: Date(timeIntervalSince1970: TimeInterval(fixtureNow)))
        let sections = snapshot.sections.map { $0.monitors.map(\.id) }
        let stops = IdleTour.stops(leading: [], sections: sections, columns: 5)
        for section in sections {
            XCTAssertFalse(Set(section).isDisjoint(with: stops))
        }
        XCTAssertGreaterThan(stops.count, sections.count)
    }
}
