import XCTest
@testable import FlareStatusKit

final class DecodingTests: XCTestCase {
    func testStockCompactedPage() throws {
        let payload = try PageParser.parse(html: Fixture.text("page-d1.html"))
        let snapshot = payload.snapshot

        XCTAssertEqual(payload.buildID, "fixtureBuild01")
        XCTAssertEqual(snapshot.format, .compacted)
        XCTAssertEqual(snapshot.lastUpdate, fixtureNow - 30)
        XCTAssertEqual(snapshot.monitors.map(\.id), ["web", "api", "db", "fresh"])
        XCTAssertEqual(snapshot.monitors.map(\.name), ["Website", "Public API", "Database", "Brand new monitor"])

        let web = try XCTUnwrap(snapshot.monitor(id: "web"))
        XCTAssertEqual(web.tooltip, "Checks the home page")
        XCTAssertEqual(web.statusPageLink, "https://example.com")
        XCTAssertFalse(web.hideLatencyChart)
        XCTAssertEqual(web.isUp, true)
        XCTAssertEqual(web.incidents.count, 2)
        XCTAssertTrue(web.incidents[0].isPlaceholder)
        XCTAssertEqual(web.outages.count, 1)
        XCTAssertEqual(web.outages[0].starts, [fixtureNow - 864_000, fixtureNow - 864_000 + 600])
        XCTAssertEqual(web.outages[0].end, fixtureNow - 864_000 + 3600)
        XCTAssertEqual(web.outages[0].errors, ["HTTP 502", "Timeout after 10000ms"])
        // Run-length-encoded locations and little-endian hex arrays.
        XCTAssertEqual(web.latency.map(\.ping), [120, 131, 118, 400, 125])
        XCTAssertEqual(web.latency.map(\.location), ["SEA", "SEA", "SEA", "FRA", "SEA"])
        XCTAssertEqual(web.latency.map(\.time), [720, 540, 360, 180, 60].map { fixtureNow - $0 })

        let api = try XCTUnwrap(snapshot.monitor(id: "api"))
        XCTAssertEqual(api.isUp, false)
        XCTAssertEqual(api.currentError, "Connection refused")
        XCTAssertEqual(api.downSince, fixtureNow - 1800)
        XCTAssertEqual(api.latency.map(\.ping), [4764, 65535, 0])

        let db = try XCTUnwrap(snapshot.monitor(id: "db"))
        XCTAssertTrue(db.hideLatencyChart)
        XCTAssertTrue(db.isHeartbeat)
        XCTAssertTrue(db.outages.isEmpty)

        let fresh = try XCTUnwrap(snapshot.monitor(id: "fresh"))
        XCTAssertNil(fresh.isUp)
        XCTAssertNil(fresh.uptimePercent(now: fixtureNow))
        XCTAssertEqual(snapshot.status(of: fresh, at: Date()), .unknown)

        XCTAssertEqual(snapshot.downCount, 1)
        XCTAssertEqual(snapshot.upCount, 2)
    }

    func testLegacyKVPageDecodesToTheSameModel() throws {
        let modern = try PageParser.parse(html: Fixture.text("page-d1.html")).snapshot
        let legacy = try PageParser.parse(html: Fixture.text("page-kv-legacy.html")).snapshot

        XCTAssertEqual(legacy.format, .legacy)
        XCTAssertEqual(legacy.buildID, "fixtureLegacy01")
        XCTAssertEqual(legacy.monitors, modern.monitors)
        XCTAssertEqual(legacy.lastUpdate, modern.lastUpdate)
        // An open incident has no `end` key at all in the legacy format.
        XCTAssertEqual(legacy.monitor(id: "api")?.isUp, false)
    }

    func testPageWithoutStoredState() throws {
        XCTAssertThrowsError(try PageParser.parse(html: Fixture.text("page-no-state.html"))) {
            XCTAssertEqual($0 as? DecodingFailure, .noDataYet)
        }
    }

    func testCorruptStateIsReportedNotCrashed() throws {
        XCTAssertThrowsError(try PageParser.parse(html: Fixture.text("page-d1-corrupt.html"))) { error in
            guard case .malformedState(let reason)? = error as? DecodingFailure else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertTrue(reason.contains("lengths"), reason)
        }
    }

    func testPagesThatAreNotUptimeFlare() throws {
        for name in ["page-not-nextjs.html", "page-other-nextjs.html"] {
            XCTAssertThrowsError(try PageParser.parse(html: Fixture.text(name)), name) { error in
                guard case .notUptimeFlare? = error as? DecodingFailure else {
                    return XCTFail("\(name): unexpected error \(error)")
                }
            }
        }
        XCTAssertThrowsError(try PageParser.parse(html: "")) { error in
            guard case .notUptimeFlare? = error as? DecodingFailure else { return XCTFail("\(error)") }
        }
    }

    func testMalformedInputs() {
        let cases = [
            #"<script id="__NEXT_DATA__" type="application/json">{not json</script>"#,
            #"<script id="__NEXT_DATA__" type="application/json">[]</script>"#,
            #"<script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"monitors":"nope"}}}</script>"#,
            #"<script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"monitors":[],"compactedStateStr":"{broken"}}}</script>"#,
            #"<script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"monitors":[],"compactedStateStr":"{\"lastUpdate\":5,\"incident\":{\"a\":{\"start\":[[1]],\"end\":[],\"error\":[]}}}"}}}</script>"#,
            #"<script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"monitors":[],"compactedStateStr":"{\"lastUpdate\":5,\"latency\":{\"a\":{\"loc\":{\"v\":[\"X\"],\"c\":[1]},\"ping\":\"zz00\",\"time\":\"00000000\"}}}"}}}</script>"#,
            #"<script id="__NEXT_DATA__" type="application/json">"#,
        ]
        for html in cases {
            XCTAssertThrowsError(try PageParser.parse(html: html), html) { error in
                XCTAssertTrue(error is DecodingFailure, "\(error)")
            }
        }
    }

    func testStateWithUnknownMonitorsAndFloatNumbers() throws {
        let state = #"{"lastUpdate":1780000000.0,"overallUp":1,"overallDown":0,"incident":{"gone":{"start":[[5]],"end":[5],"error":[["dummy"]]}},"latency":{},"extra":true}"#
        let next: [String: Any] = [
            "buildId": "b",
            "props": ["pageProps": ["compactedStateStr": state, "monitors": [["id": "only"]]]],
        ]
        let payload = try PageParser.parse(nextData: JSONSerialization.data(withJSONObject: next))
        XCTAssertEqual(payload.snapshot.lastUpdate, 1_780_000_000)
        XCTAssertEqual(payload.snapshot.monitors.map(\.name), ["only"], "a monitor without a name falls back to its id")
        XCTAssertNil(payload.snapshot.monitors[0].isUp)
    }

    func testHexDecoding() {
        XCTAssertEqual(Hex.littleEndianIntegers("7800ffff", width: 2), [120, 65535])
        XCTAssertEqual(Hex.littleEndianIntegers("00E1F505", width: 4), [100_000_000])
        XCTAssertEqual(Hex.littleEndianIntegers("", width: 4), [])
        XCTAssertNil(Hex.littleEndianIntegers("780", width: 2))
        XCTAssertNil(Hex.littleEndianIntegers("78zz", width: 2))
    }

    func testScriptSources() throws {
        let sources = PageParser.scriptSources(in: try Fixture.text("page-d1.html"))
        XCTAssertTrue(sources.contains("/_next/static/chunks/469-5555.js"))
        XCTAssertEqual(sources.count, 8)
    }
}
