import XCTest

final class IdleTourUITests: RemoteTestCase {
    /// With nobody at the remote the display must walk through the whole page,
    /// reach the last group, and start again from the top.
    func testIdleTourVisitsEveryGroupAndLoops() {
        launch(demo: "large", ["-idleSeconds", "3", "-tourSeconds", "2.5"])
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 30))
        let groups = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'group-'"))
        XCTAssertTrue(groups.firstMatch.waitForExistence(timeout: 10))
        let groupNames = groups.allElementsBoundByIndex.map(\.label)
        XCTAssertGreaterThan(groupNames.count, 2, "the page should have several groups: \(groupNames)")

        // Put the remote down and watch.
        var visited: [String] = []
        var visibleGroups = Set<String>()
        var looped = false
        let first = focusedName
        let deadline = Date().addingTimeInterval(150)
        while Date() < deadline {
            let name = focusedName
            if !name.isEmpty, visited.last != name {
                visited.append(name)
                // The scroll that follows the focus is animated; let it land.
                pause(1)
                XCTAssertTrue(focusedName != name || focused.isHittable, "the tour focused \"\(name)\" but it is not on screen")
                if visited.count == 4 { screenshot("idle-tour-position-1") }
                if visited.count == 9 { screenshot("idle-tour-position-2") }
            }
            for group in groups.allElementsBoundByIndex where group.isHittable { visibleGroups.insert(group.label) }
            if visited.count > 3, name == visited[1], visibleGroups.count == groupNames.count {
                looped = true
                break
            }
            pause(0.5)
        }
        XCTAssertGreaterThan(visited.count, 5, "the focus barely moved: started on \"\(first)\", visited \(visited)")
        XCTAssertEqual(visibleGroups, Set(groupNames), "groups never shown: \(Set(groupNames).subtracting(visibleGroups)); visited \(visited)")
        XCTAssertTrue(looped, "the tour did not come back to its first stop; visited \(visited)")
    }

    /// Picking the remote up stops the tour at once; it starts again only
    /// after the idle time has passed.
    func testTheTourYieldsToThePersonWithTheRemote() {
        launch(demo: "large", ["-idleSeconds", "6", "-tourSeconds", "1"])
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 30))
        let start = focusedName

        // Wait for the tour to start moving.
        let moving = Date().addingTimeInterval(30)
        while Date() < moving, focusedName == start { pause(0.5) }
        XCTAssertNotEqual(focusedName, start, "the tour never started")
        pause(2.5)

        // A person presses a button: focus goes where they sent it and stays.
        remote.press(.right)
        pause(0.6)
        let chosen = focusedName
        for _ in 0..<6 {
            pause(0.5)
            XCTAssertEqual(focusedName, chosen, "the tour moved the focus while the remote was in use")
        }

        // Left alone again, the tour resumes.
        let resumed = Date().addingTimeInterval(30)
        while Date() < resumed, focusedName == chosen { pause(0.5) }
        XCTAssertNotEqual(focusedName, chosen, "the tour did not resume after the idle time")
    }
}
