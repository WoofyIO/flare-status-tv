import XCTest
@testable import FlareStatusKit

final class LiveDataTests: XCTestCase {
    func testCurrentAPIShape() throws {
        let live = try LiveData.parse(Fixture.data("api-data.json"))
        XCTAssertEqual(live.up, 2)
        XCTAssertEqual(live.down, 1)
        XCTAssertEqual(live.updatedAt, fixtureNow)
        XCTAssertEqual(live.monitors["web"], LiveStatus(up: true, latency: 125, location: "SEA", message: "OK"))
        XCTAssertEqual(live.monitors["api"]?.up, false)
        XCTAssertEqual(live.monitors["api"]?.message, "Connection refused")

        // The entry with an unreadable start is dropped, the rest survive.
        let maintenances = try XCTUnwrap(live.maintenances)
        XCTAssertEqual(maintenances.count, 2)
        XCTAssertEqual(maintenances[0].title, "Upgrade")
        XCTAssertEqual(maintenances[0].monitorIDs, ["db"])
        XCTAssertEqual(maintenances[0].start.timeIntervalSince1970, 1_779_962_400) // ISO 8601 string
        XCTAssertEqual(maintenances[0].end?.timeIntervalSince1970, 1_780_010_000) // millisecond number
        XCTAssertNil(maintenances[1].title)
        XCTAssertNil(maintenances[1].end)
        XCTAssertEqual(maintenances[1].start.timeIntervalSince1970, TimeInterval(fixtureNow - 3600)) // seconds number
    }

    func testOlderAPIWithoutMaintenances() throws {
        let live = try LiveData.parse(Fixture.data("api-data-legacy.json"))
        XCTAssertNil(live.maintenances)
        XCTAssertEqual(live.monitors.count, 3)
    }

    func testNoDataAndGarbage() throws {
        XCTAssertThrowsError(try LiveData.parse(Fixture.data("api-no-data.json"))) {
            XCTAssertEqual($0 as? DecodingFailure, .noDataYet)
        }
        for body in ["", "<html>", "[]", #"{"hello":"world"}"#, #"{"monitors":{"a":5},"updatedAt":1}"#] {
            XCTAssertThrowsError(try LiveData.parse(Data(body.utf8)), body) { error in
                guard case .notUptimeFlare? = error as? DecodingFailure else { return XCTFail("\(body): \(error)") }
            }
        }
    }

    func testFlexibleDates() {
        XCTAssertEqual(FlexibleDate.parse("2026-05-28T10:00:00Z")?.timeIntervalSince1970, 1_779_962_400)
        XCTAssertEqual(FlexibleDate.parse("2026-05-28T18:00:00.000+08:00")?.timeIntervalSince1970, 1_779_962_400)
        XCTAssertNotNil(FlexibleDate.parse("2026-05-28 10:00"))
        XCTAssertNil(FlexibleDate.parse("soon"))
    }

    func testMergingLiveDataIntoASnapshot() throws {
        let snapshot = try PageParser.parse(html: Fixture.text("page-d1.html")).snapshot
        var live = try LiveData.parse(Fixture.data("api-data.json"))

        // Same states as the stored history: nothing to re-fetch. ("fresh" has
        // no data on either side, but the monitor lists differ, so add it.)
        live.monitors["fresh"] = LiveStatus(up: true, latency: 1, location: "SEA", message: "OK")
        var merged = snapshot.applying(live)
        XCTAssertEqual(merged.snapshot.lastUpdate, fixtureNow)
        XCTAssertEqual(merged.snapshot.maintenances.count, 2)
        XCTAssertEqual(merged.snapshot.monitor(id: "web")?.currentPing, 125)
        XCTAssertEqual(merged.snapshot.monitor(id: "fresh")?.isUp, true)
        XCTAssertFalse(merged.needsFullRefresh)
        let dbStatus = merged.snapshot.status(of: try XCTUnwrap(merged.snapshot.monitor(id: "db")), at: Date(timeIntervalSince1970: 1_779_970_000))
        XCTAssertEqual(dbStatus, .maintenance)

        // A monitor recovered: shown at once, and the history is re-fetched.
        live.monitors["api"] = LiveStatus(up: true, latency: 80, location: "NRT", message: "OK")
        merged = snapshot.applying(live)
        XCTAssertEqual(merged.snapshot.monitor(id: "api")?.isUp, true)
        XCTAssertEqual(merged.snapshot.downCount, 0)
        XCTAssertTrue(merged.needsFullRefresh)

        // The monitor list changed.
        live.monitors["added"] = LiveStatus(up: true, latency: 1, location: "SEA", message: "OK")
        XCTAssertTrue(snapshot.applying(live).needsFullRefresh)

        // Older live data never rolls the snapshot back.
        live.updatedAt = fixtureNow - 500
        live.monitors["web"] = LiveStatus(up: false, latency: nil, location: nil, message: "old")
        XCTAssertEqual(snapshot.applying(live).snapshot.monitor(id: "web")?.isUp, true)
    }
}
