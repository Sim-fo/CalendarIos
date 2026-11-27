import XCTest

final class WeeklyGesturesUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()

        let metrics = app.staticTexts["weekly.metrics"]
        XCTAssertTrue(metrics.waitForExistence(timeout: 8), "Weekly view should appear on launch")
    }

    private struct WeeklyMetrics {
        let hour: Int
        let day: Int
        let scrollY: Int
        let scrollX: Int
    }

    private func readMetrics() -> WeeklyMetrics {
        let label = app.staticTexts["weekly.metrics"].label
        var dict: [String: Int] = [:]
        for pair in label.split(separator: ",") {
            let kv = pair.split(separator: "=")
            if kv.count == 2, let val = Int(kv[1]) {
                dict[String(kv[0])] = val
            }
        }
        return WeeklyMetrics(
            hour: dict["hour"] ?? -1,
            day: dict["day"] ?? -1,
            scrollY: dict["scrollY"] ?? -1,
            scrollX: dict["scrollX"] ?? -1
        )
    }

    private var eventCreateSheetExists: Bool {
        app.buttons["weekly.eventCreateUniqueButton"].exists || app.staticTexts["weekly.eventCreateTime"].exists
    }

    private func timelineElement() -> XCUIElement {
        let verticalScroll = app.scrollViews["weekly.verticalScroll"]
        if verticalScroll.exists {
            return verticalScroll
        }
        return app.scrollViews.firstMatch
    }

    // MARK: - 1. Pinch-to-zoom works BOTH IN and OUT and never triggers Event Create or Day Navigation

    func testPinchZoomChangesScaleWithoutFalseEventCreation() {
        let timeline = timelineElement()
        XCTAssertTrue(timeline.waitForExistence(timeout: 5), "Timeline scroll view should exist")

        let before = readMetrics()
        XCTAssertGreaterThan(before.hour, 0, "Initial metrics: \(before)")

        // Pinch zoom IN (2 fingers spreading apart inside timeline)
        timeline.pinch(withScale: 1.75, velocity: 1.5)
        usleep(450_000)

        XCTAssertFalse(eventCreateSheetExists, "Pinch zoom-in must NOT open EventCreateView")
        XCTAssertTrue(app.staticTexts["weekly.metrics"].exists, "Pinch zoom-in must stay on Weekly view")

        let afterZoomIn = readMetrics()
        XCTAssertTrue(
            afterZoomIn.hour > before.hour || afterZoomIn.day > before.day,
            "Pinch zoom-in should increase hourHeight or dayColumnWidth (before=\(before), after=\(afterZoomIn))"
        )

        // Pinch zoom OUT (2 fingers pinching together strictly inside timeline)
        timeline.pinch(withScale: 0.55, velocity: -1.5)
        usleep(450_000)

        XCTAssertFalse(eventCreateSheetExists, "Pinch zoom-out must NOT open EventCreateView")
        XCTAssertTrue(app.staticTexts["weekly.metrics"].exists, "Pinch zoom-out must stay on Weekly view")

        let afterZoomOut = readMetrics()
        XCTAssertTrue(
            afterZoomOut.hour < afterZoomIn.hour || afterZoomOut.day < afterZoomIn.day,
            "Pinch zoom-out should decrease hourHeight or dayColumnWidth (before=\(afterZoomIn), after=\(afterZoomOut))"
        )
    }

    // MARK: - 2. Vertical and horizontal scrolling work cleanly without false triggers

    func testVerticalAndHorizontalScrollingWithoutFalseEventCreation() {
        let window = app.windows.firstMatch
        let before = readMetrics()

        // Vertical swipe up (scroll down timeline)
        let startV = window.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.72))
        let endV = window.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.30))
        startV.press(forDuration: 0.02, thenDragTo: endV)
        usleep(500_000)

        XCTAssertFalse(eventCreateSheetExists, "Vertical scroll must NOT open EventCreateView")
        let afterV = readMetrics()
        XCTAssertGreaterThan(afterV.scrollY, before.scrollY, "Vertical scroll should increase scrollY (before=\(before), after=\(afterV))")

        // Horizontal swipe left (scroll days forward)
        let startH = window.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.50))
        let endH = window.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.50))
        startH.press(forDuration: 0.02, thenDragTo: endH)
        usleep(500_000)

        XCTAssertFalse(eventCreateSheetExists, "Horizontal scroll must NOT open EventCreateView")
        let afterH = readMetrics()
        XCTAssertNotEqual(afterH.scrollX, afterV.scrollX, "Horizontal scroll should change scrollX (before=\(afterV), after=\(afterH))")
    }

    // MARK: - 3. Single-finger long-press + drag opens EventCreateView cleanly

    func testSingleFingerLongPressAndDragOpensEventCreate() {
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.42))
        let uniqueButton = app.buttons["weekly.eventCreateUniqueButton"]

        // 1. Stationary single-finger long-press opens EventCreateView
        start.press(forDuration: 0.8)
        XCTAssertTrue(uniqueButton.waitForExistence(timeout: 4), "Stationary long-press should open EventCreateView")

        // Dismiss sheet cleanly
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["weekly.metrics"].waitForExistence(timeout: 3))

        // 2. Single-finger long-press + drag down opens EventCreateView at dragged time
        let dragTarget = window.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.56))
        start.press(forDuration: 0.8, thenDragTo: dragTarget, withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(uniqueButton.waitForExistence(timeout: 4), "Long-press + drag should open EventCreateView")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["weekly.metrics"].waitForExistence(timeout: 3))
    }

    // MARK: - 4. Single-finger tap on a visible day header opens Daily View

    func testSingleTapOnDayHeaderOpensDailyView() {
        let windowFrame = app.windows.firstMatch.frame
        let headers = app.buttons.matching(identifier: "weekly.dayHeader").allElementsBoundByIndex
        // Check frame bounds FIRST (calling .isHittable on offscreen buttons fails in XCTest!)
        let visibleHeader = headers.first { header in
            let frame = header.frame
            return frame.width > 10 && frame.minX >= 64 && frame.maxX <= windowFrame.width - 8
        }
        guard let targetHeader = visibleHeader else {
            XCTFail("Expected at least one visible day header (found \(headers.count) total)")
            return
        }

        targetHeader.tap()

        let disappeared = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: app.staticTexts["weekly.metrics"]
        )
        wait(for: [disappeared], timeout: 4)
    }
}
