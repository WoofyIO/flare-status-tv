import XCTest

/// Drives the app the way a person does: with the Siri Remote.
class RemoteTestCase: XCTestCase {
    let app = XCUIApplication()
    let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
    }

    /// Launches with invented sample data unless `TEST_RUNNER_STATUS_URL` names
    /// a real status page (pass it on the xcodebuild command line; never commit one).
    func launch(demo: String, _ extra: [String] = []) {
        var arguments = extra
        if let url = ProcessInfo.processInfo.environment["STATUS_URL"], !url.isEmpty {
            arguments += ["-url", url]
        } else {
            arguments += ["-demo", demo]
        }
        app.launchArguments = arguments
        app.launch()
    }

    var focused: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    /// A short description of what has focus, for assertions and failure messages.
    var focusedName: String {
        let element = focused
        guard element.exists else { return "" }
        return element.identifier.isEmpty ? element.label : element.identifier
    }

    /// Whether the focus is on the element with this identifier or visible text.
    /// (In a settings list the focus sits on the row, which carries the text
    /// of the button inside it.)
    func focusIs(on text: String) -> Bool {
        let element = focused
        guard element.exists else { return false }
        return element.identifier == text || element.label == text || element.label.hasPrefix(text + ",")
    }

    /// Presses a remote button until `condition` holds; fails after `limit` presses.
    func press(_ button: XCUIRemote.Button, until condition: () -> Bool, limit: Int = 25, _ what: String,
               file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<limit {
            if condition() { return }
            remote.press(button)
            pause(0.4)
        }
        XCTAssertTrue(condition(), "\(what); focus ended on \"\(focusedName)\"", file: file, line: line)
    }

    func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Keeps a screenshot in the test report and, when `TEST_RUNNER_SCREENSHOT_DIR`
    /// is set, also writes it there as a PNG.
    func screenshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !directory.isEmpty {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")
            try? shot.pngRepresentation.write(to: url)
        }
    }
}
