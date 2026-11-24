import XCTest

final class SettingsUITests: RemoteTestCase {
    private var refreshRow: XCUIElement { app.buttons["settings-refresh-every"] }

    /// Reaches Settings the way a person does: up to the gear, then select.
    private func openSettingsWithTheRemote() {
        launch(demo: "healthy")
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 30))
        press(.up, until: { app.buttons["Settings"].hasFocus }, "the gear should be reachable by pressing up")
        remote.press(.select)
        XCTAssertTrue(refreshRow.waitForExistence(timeout: 5), "Settings did not open")
    }

    private func chooseInterval(_ label: String) {
        press(.down, until: { focusIs(on: "Refresh every") }, "focus should reach Refresh every")
        remote.press(.select)
        XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 5), "interval \(label) is not offered")
        press(.down, until: { focusIs(on: label) || focusIs(on: "5 min") }, "focus should move down the intervals")
        press(.up, until: { focusIs(on: label) }, "focus should reach \(label)")
        remote.press(.select)
        // Choosing returns to Settings, which shows the new value.
        XCTAssertTrue(refreshRow.waitForExistence(timeout: 5), "choosing an interval should return to Settings")
        XCTAssertTrue(refreshRow.label.contains(label), "Settings shows \"\(refreshRow.label)\"")
    }

    func testRefreshIntervalCanBeChosen() {
        openSettingsWithTheRemote()
        press(.down, until: { focusIs(on: "Refresh every") }, "focus should reach Refresh every")
        XCTAssertTrue(refreshRow.label.contains("1 min"), "the default should be 1 min, not \"\(refreshRow.label)\"")
        remote.press(.select)

        for option in ["30 s", "1 min", "2 min", "5 min"] {
            XCTAssertTrue(app.buttons[option].waitForExistence(timeout: 5), "interval \(option) is not offered")
            XCTAssertTrue(app.buttons[option].isHittable, "interval \(option) is off screen")
        }
        XCTAssertEqual(app.buttons["1 min"].value as? String, "selected")
        screenshot("settings-refresh-interval-options")
        remote.press(.menu)
        XCTAssertTrue(refreshRow.waitForExistence(timeout: 5), "Menu should return to Settings")

        chooseInterval("5 min")
        screenshot("settings-after-choosing-5-min")

        // And it is stored: still there after the app is restarted.
        app.terminate()
        app.launchArguments = ["-demo", "healthy", "-open", "settings"]
        app.launch()
        XCTAssertTrue(refreshRow.waitForExistence(timeout: 30))
        XCTAssertTrue(refreshRow.label.contains("5 min"), "after a restart Settings shows \"\(refreshRow.label)\"")

        // Put the default back for the next run.
        chooseInterval("1 min")
    }

    func testEverythingInSettingsCanBeReached() {
        openSettingsWithTheRemote()
        // Keep pressing down: focus must get past "Refresh now" to the last row.
        var seen: [String] = []
        for _ in 0..<20 {
            let name = focusedName
            if seen.last != name { seen.append(name) }
            if focusIs(on: "About Flare Status") { break }
            remote.press(.down)
            pause(0.4)
        }
        XCTAssertTrue(focusIs(on: "About Flare Status"), "focus stopped early; visited \(seen)")
        XCTAssertTrue(seen.contains("Refresh now"), "visited \(seen)")
        XCTAssertTrue(app.buttons["settings-about"].isHittable, "the last row is off screen")
        screenshot("settings-scrolled-to-about")

        remote.press(.select)
        let note = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'unofficial'")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5), "the About text is not shown")
        XCTAssertTrue(note.isHittable, "the About text is off screen")
        XCTAssertTrue(app.staticTexts["Version"].isHittable)
        XCTAssertTrue(app.staticTexts["Data format"].isHittable)
        screenshot("settings-about")

        remote.press(.menu)
        XCTAssertTrue(refreshRow.waitForExistence(timeout: 5), "Menu should return to Settings")

        // And back up to the top.
        press(.up, until: { focusIs(on: "Example Status") }, "focus should climb back to the page list")
    }
}
