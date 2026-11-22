import XCTest
@testable import FlareStatusKit

final class PageConfigTests: XCTestCase {
    func testReadsTitleAndGroupsFromACompiledChunk() throws {
        let info = try XCTUnwrap(PageConfigReader.read(
            javascript: Fixture.text("config-chunk.js"), knownMonitorIDs: ["web", "api", "db", "fresh"]))
        XCTAssertEqual(info.title, "Example \u{2014} Status")
        XCTAssertEqual(info.groups.map(\.name), ["Website", "APIs & data", "Caf\u{e9}"])
        XCTAssertEqual(info.groups.map(\.monitorIDs), [["web"], ["api", "db"], ["fresh"]])
    }

    func testIgnoresGroupsThatNameNoKnownMonitor() throws {
        XCTAssertNil(PageConfigReader.read(javascript: try Fixture.text("config-chunk.js"), knownMonitorIDs: ["x"]))
    }

    func testUngroupedPage() throws {
        let script = try Fixture.text("config-chunk-ungrouped.js")
        XCTAssertNil(PageConfigReader.read(javascript: script, knownMonitorIDs: ["web"]))
        XCTAssertEqual(PageConfigReader.readTitleOnly(javascript: script), "Plain page")
    }

    func testHostileOrOddScriptsDoNotCrash() {
        let ids: Set<String> = ["a"]
        for script in [
            "", "group:", "group:{", "group:{a:", "group:{a:[", #"group:{a:["a""#, #"group:{a:["a",}"#,
            "group:{a:[1,2]}", #"group:{"a":["a\"#, #"group:{a:["\u12"]}"#, "group:{a:[`a`]}  group:{}",
            String(repeating: "group:{", count: 2000),
        ] {
            _ = PageConfigReader.read(javascript: script, knownMonitorIDs: ids)
        }
        XCTAssertEqual(
            PageConfigReader.read(javascript: "x={group:{ 'A b' : [ 'a' , \"c\" ] , $k_1:['a'] }}", knownMonitorIDs: ids)?.groups.map(\.name),
            ["A b", "$k_1"])
        XCTAssertEqual(
            PageConfigReader.read(javascript: #"group:{"🚀 Launch":["a"]}"#, knownMonitorIDs: ids)?.groups.first?.name,
            "\u{1F680} Launch")
    }
}
