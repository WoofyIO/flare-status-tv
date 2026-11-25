import XCTest

/// The path someone without an UptimeFlare deployment takes: first run,
/// "Try with sample data", look around, and back to setup.
final class SampleDataUITests: RemoteTestCase {
    private var trySample: XCUIElement { app.buttons["setup-try-sample"] }
    private var badge: XCUIElement { app.buttons["sample-data-badge"] }

    /// Starts as a first run: no stored pages, no launch-argument data.
    private func launchFirstRun() {
        app.launchArguments = ["-pages", "", "-selectedPage", ""]
        app.launch()
        XCTAssertTrue(trySample.waitForExistence(timeout: 30), "the first-run screen should offer sample data")
        XCTAssertTrue(app.textFields.firstMatch.exists, "the first-run screen should ask for an address")
    }

    private func startSample() {
        press(.down, until: { trySample.hasFocus }, "focus should reach Try with sample data")
        remote.press(.select)
        XCTAssertTrue(badge.waitForExistence(timeout: 10), "the dashboard should say it is showing sample data")
    }

    func testSampleDataFromFirstRunAndBackFromTheDashboard() {
        launchFirstRun()
        screenshot("first-run-with-sample-data-button")
        startSample()

        // A dashboard with something to look at, and plainly labelled.
        XCTAssertTrue(badge.label.contains("Sample data"), "badge reads \"\(badge.label)\"")
        XCTAssertTrue(app.staticTexts["down-now"].exists, "the sample should include an outage")
        XCTAssertTrue(app.buttons["monitor-homepage"].exists)
        XCTAssertTrue(app.buttons["monitor-homepage"].label.contains("operational"), "tile reads \"\(app.buttons["monitor-homepage"].label)\"")
        XCTAssertTrue(app.buttons["down-payments-api"].label.contains("down"), "tile reads \"\(app.buttons["down-payments-api"].label)\"")
        screenshot("sample-data-dashboard")

        // The detail screen works on sample data too.
        press(.down, until: { focusedName.hasPrefix("down-") || focusedName.hasPrefix("monitor-") }, limit: 3, "a tile should have focus")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Daily uptime"].waitForExistence(timeout: 5), "the detail screen did not open")
        remote.press(.menu)
        XCTAssertTrue(badge.waitForExistence(timeout: 5))

        // Back to setup from the badge.
        press(.up, until: { badge.hasFocus || app.buttons["Settings"].hasFocus }, "the top bar should be reachable")
        press(.left, until: { badge.hasFocus }, "the sample data badge should be reachable")
        remote.press(.select)
        XCTAssertTrue(trySample.waitForExistence(timeout: 5), "leaving sample data should return to setup")
        XCTAssertFalse(badge.exists)
    }

    func testLeavingSampleDataFromSettings() {
        launchFirstRun()
        startSample()
        press(.up, until: { badge.hasFocus || app.buttons["Settings"].hasFocus }, "the top bar should be reachable")
        press(.right, until: { app.buttons["Settings"].hasFocus }, "the gear should be reachable")
        remote.press(.select)
        XCTAssertTrue(app.buttons["settings-leave-sample"].waitForExistence(timeout: 5), "Settings should offer to leave sample data")
        press(.up, until: { focusIs(on: "Leave sample data") }, "focus should reach Leave sample data")
        remote.press(.select)
        XCTAssertTrue(trySample.waitForExistence(timeout: 5), "leaving sample data should return to setup")
    }
}
