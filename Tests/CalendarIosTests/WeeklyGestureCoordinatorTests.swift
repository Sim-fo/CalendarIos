import UIKit
import XCTest
@testable import CalendarIos

@MainActor
final class WeeklyGestureCoordinatorTests: XCTestCase {
    func testSecondFingerImmediatelyEntersZoomExclusiveAndCancelsSlotSelection() {
        var now: CFTimeInterval = 100
        let coordinator = WeeklyGestureCoordinator(postZoomCooldownSeconds: 0.2, nowProvider: { now })
        var didEnterZoomExclusive = false
        coordinator.onEnterZoomExclusive = { didEnterZoomExclusive = true }

        // First finger touches down & starts slot selection
        coordinator.updateActiveTouchCount(1)
        XCTAssertTrue(coordinator.canHandleSingleTouch)
        XCTAssertTrue(coordinator.tryStartSlotSelection())
        XCTAssertEqual(coordinator.mode, .slotSelection)
        XCTAssertTrue(coordinator.isBlockingScroll)

        // Second finger touches down anywhere on timeline -> immediately zoomExclusive!
        coordinator.updateActiveTouchCount(2)
        XCTAssertTrue(didEnterZoomExclusive)
        XCTAssertTrue(coordinator.isZoomExclusive)
        XCTAssertFalse(coordinator.canHandleSingleTouch)
        XCTAssertFalse(coordinator.tryStartSlotSelection())
        XCTAssertFalse(coordinator.tryStartEventDrag())
    }

    func testZoomExclusiveStaysStickyWhenOneFingerLiftsBeforeSecondAndEnforcesCooldown() {
        var now: CFTimeInterval = 200
        let coordinator = WeeklyGestureCoordinator(postZoomCooldownSeconds: 0.25, nowProvider: { now })

        let hScroll = UIScrollView()
        let vScroll = UIScrollView()
        coordinator.bindScrollViews(horizontal: hScroll, vertical: vScroll)

        coordinator.updateActiveTouchCount(1)
        coordinator.updateActiveTouchCount(2)
        XCTAssertTrue(coordinator.isZoomExclusive)
        XCTAssertFalse(hScroll.isScrollEnabled)
        XCTAssertFalse(vScroll.isScrollEnabled)

        // One finger lifts (1 finger remains resting on screen) -> MUST stay zoomExclusive!
        coordinator.updateActiveTouchCount(1)
        XCTAssertTrue(coordinator.isZoomExclusive)
        XCTAssertFalse(coordinator.canHandleSingleTouch)
        XCTAssertFalse(coordinator.tryStartSlotSelection())
        XCTAssertFalse(coordinator.tryStartEventDrag())
        XCTAssertFalse(hScroll.isScrollEnabled)

        // Final finger lifts -> exits zoomExclusive, restores scrolling, enters post-zoom cooldown
        coordinator.updateActiveTouchCount(0)
        XCTAssertFalse(coordinator.isZoomExclusive)
        XCTAssertTrue(hScroll.isScrollEnabled)
        XCTAssertTrue(vScroll.isScrollEnabled)
        XCTAssertTrue(coordinator.isInPostZoomCooldown)
        XCTAssertFalse(coordinator.canHandleSingleTouch)
        XCTAssertFalse(coordinator.tryStartSlotSelection())

        // After cooldown elapses, single-touch interactions work normally again
        now += 0.30
        XCTAssertFalse(coordinator.isInPostZoomCooldown)
        XCTAssertTrue(coordinator.canHandleSingleTouch)
        XCTAssertTrue(coordinator.tryStartSlotSelection())
        coordinator.finishInteraction(owner: .emptySlot)
        XCTAssertEqual(coordinator.mode, .idle)
    }

    func testSecondFingerCancelsActiveEventDragAndForceResetClearsState() {
        var now: CFTimeInterval = 300
        let coordinator = WeeklyGestureCoordinator(postZoomCooldownSeconds: 0.2, nowProvider: { now })

        coordinator.updateActiveTouchCount(1)
        XCTAssertTrue(coordinator.tryStartEventDrag())
        XCTAssertEqual(coordinator.mode, .eventDrag)

        coordinator.updateActiveTouchCount(2)
        XCTAssertEqual(coordinator.mode, .zoomExclusive)
        XCTAssertFalse(coordinator.canHandleSingleTouch)

        // App resigns active / tab switch -> forceReset clears everything immediately
        coordinator.forceReset()
        XCTAssertEqual(coordinator.mode, .idle)
        XCTAssertEqual(coordinator.activeTouchCount, 0)
        XCTAssertTrue(coordinator.canHandleSingleTouch)
    }

    func testWindowEndAllTouchesDoesNotAbortActiveSlotSelectionBeforeRecognizerEnds() {
        let coordinator = WeeklyGestureCoordinator()
        coordinator.updateActiveTouchCount(1)
        XCTAssertTrue(coordinator.tryStartSlotSelection())
        XCTAssertEqual(coordinator.mode, .slotSelection)

        // Window-level MultiTouchObserver sees touchesEnded BEFORE child UILongPressGestureRecognizer.ended
        coordinator.updateActiveTouchCount(0)
        // Mode MUST remain .slotSelection so child recognizer commits cleanly!
        XCTAssertEqual(coordinator.mode, .slotSelection)

        // Child recognizer commits and calls finishInteraction
        coordinator.finishInteraction(owner: .emptySlot)
        XCTAssertEqual(coordinator.mode, .idle)
    }
}
