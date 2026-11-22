import XCTest
@testable import FlareStatusKit

final class ModelTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testUptimePercentMatchesTheWebPageFormula() throws {
        let snapshot = try PageParser.parse(html: Fixture.text("page-d1.html")).snapshot
        // web: monitored 90 days, down for one hour.
        let web = try XCTUnwrap(snapshot.monitor(id: "web"))
        XCTAssertEqual(try XCTUnwrap(web.uptimePercent(now: fixtureNow)), (1 - 3600.0 / (90 * 86_400)) * 100, accuracy: 1e-9)
        // api: monitored 30 days, down for the last 30 minutes and counting.
        let api = try XCTUnwrap(snapshot.monitor(id: "api"))
        XCTAssertEqual(try XCTUnwrap(api.uptimePercent(now: fixtureNow)), (1 - 1800.0 / (30 * 86_400)) * 100, accuracy: 1e-9)
        XCTAssertEqual(snapshot.monitor(id: "db")?.uptimePercent(now: fixtureNow), 100)
    }

    func testDailyUptime() throws {
        let snapshot = try PageParser.parse(html: Fixture.text("page-d1.html")).snapshot
        let web = try XCTUnwrap(snapshot.monitor(id: "web"))
        let days = web.dailyUptime(days: 90, now: fixtureNow, calendar: utc)
        XCTAssertEqual(days.count, 90)
        XCTAssertEqual(days.last?.dayStart, 1_779_926_400, "the last bar is today (UTC midnight)")
        let bad = days.filter { $0.downSeconds > 0 }
        XCTAssertEqual(bad.count, 1)
        XCTAssertEqual(bad[0].downSeconds, 3600)
        XCTAssertEqual(try XCTUnwrap(bad[0].percent), (1 - 3600.0 / 86_400) * 100, accuracy: 1e-9)
        XCTAssertEqual(days[45].percent, 100)

        // A monitor that has only existed for 30 days has no data before that.
        let api = try XCTUnwrap(snapshot.monitor(id: "api"))
        let apiDays = api.dailyUptime(days: 90, now: fixtureNow, calendar: utc)
        XCTAssertNil(apiDays[0].percent)
        XCTAssertNotNil(apiDays[89].percent)
        XCTAssertLessThan(try XCTUnwrap(apiDays[89].percent), 100)

        // No history at all.
        let fresh = try XCTUnwrap(snapshot.monitor(id: "fresh"))
        XCTAssertTrue(fresh.dailyUptime(days: 7, now: fixtureNow, calendar: utc).allSatisfy { $0.percent == nil })
    }

    func testSectionsFollowGroupsAndNeverHideMonitors() throws {
        var snapshot = try PageParser.parse(html: Fixture.text("page-d1.html")).snapshot
        XCTAssertEqual(snapshot.sections.count, 1)
        XCTAssertNil(snapshot.sections[0].name)

        snapshot.groups = [
            MonitorGroup(name: "Data", monitorIDs: ["db", "api", "missing"]),
            MonitorGroup(name: "Empty", monitorIDs: ["nothing"]),
            MonitorGroup(name: "Web", monitorIDs: ["web"]),
        ]
        let sections = snapshot.sections
        XCTAssertEqual(sections.map(\.name), ["Data", "Web", "Other"])
        XCTAssertEqual(sections[0].monitors.map(\.id), ["db", "api"], "group order wins over page order")
        XCTAssertEqual(sections[0].downCount, 1)
        XCTAssertEqual(sections[2].monitors.map(\.id), ["fresh"])
    }

    func testStaleness() {
        let snapshot = StatusSnapshot(lastUpdate: fixtureNow, monitors: [])
        XCTAssertFalse(snapshot.isStale(now: Date(timeIntervalSince1970: TimeInterval(fixtureNow + 299))))
        XCTAssertTrue(snapshot.isStale(now: Date(timeIntervalSince1970: TimeInterval(fixtureNow + 301))))
    }

    func testSampleDataCoversTheSizesTheAppMustHandle() {
        let now = Date(timeIntervalSince1970: TimeInterval(fixtureNow))
        XCTAssertEqual(SampleData.snapshot(.single, now: now).monitors.count, 1)
        XCTAssertTrue(SampleData.snapshot(.single, now: now).groups.isEmpty)
        XCTAssertEqual(SampleData.snapshot(.healthy, now: now).monitors.count, 15)
        XCTAssertEqual(SampleData.snapshot(.healthy, now: now).downCount, 0)
        XCTAssertEqual(SampleData.snapshot(.outage, now: now).downCount, 2)
        XCTAssertEqual(SampleData.snapshot(.large, now: now).monitors.count, 64)
        XCTAssertEqual(SampleData.snapshot(.large, now: now).downCount, 1)
        XCTAssertEqual(SampleData.snapshot(.large, now: now).sections.count, 6)
        XCTAssertEqual(SampleData.snapshot(.large, now: now), SampleData.snapshot(.large, now: now), "deterministic")
    }
}
