import XCTest
@testable import CalendarIos

final class WeeklyTimelineLayoutTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return cal
    }

    private func makeDate(hour: Int, minute: Int = 0) -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 11,
            day: 26,
            hour: hour,
            minute: minute
        )
        return calendar.date(from: components)!
    }

    func testOverlappingEventsSplitIntoSideBySideColumns() {
        let first = CalendarEvent(
            id: 1,
            eventTypeId: nil,
            customTitle: "A",
            customColorHex: 0xFF3A7AFE,
            title: "A",
            colorHex: 0xFF3A7AFE,
            startAt: makeDate(hour: 10, minute: 0),
            durationMinutes: 60,
            reminderMinutes: 0,
            note: nil
        )
        let second = CalendarEvent(
            id: 2,
            eventTypeId: nil,
            customTitle: "B",
            customColorHex: 0xFF11A36A,
            title: "B",
            colorHex: 0xFF11A36A,
            startAt: makeDate(hour: 10, minute: 30),
            durationMinutes: 60,
            reminderMinutes: 0,
            note: nil
        )
        let separate = CalendarEvent(
            id: 3,
            eventTypeId: nil,
            customTitle: "C",
            customColorHex: 0xFFEF6C3E,
            title: "C",
            colorHex: 0xFFEF6C3E,
            startAt: makeDate(hour: 13, minute: 0),
            durationMinutes: 60,
            reminderMinutes: 0,
            note: nil
        )

        let layouts = WeeklyTimelineEventLayout.make(
            events: [first, second, separate],
            calendar: calendar,
            columnWidth: 160,
            hourHeight: 60
        )

        XCTAssertEqual(layouts.count, 3)
        let layoutA = try! XCTUnwrap(layouts.first { $0.id == 1 })
        let layoutB = try! XCTUnwrap(layouts.first { $0.id == 2 })
        let layoutC = try! XCTUnwrap(layouts.first { $0.id == 3 })

        XCTAssertEqual(layoutA.y, 600, accuracy: 0.01)
        XCTAssertEqual(layoutB.y, 630, accuracy: 0.01)
        XCTAssertEqual(layoutA.width, layoutB.width, accuracy: 0.01)
        XCTAssertGreaterThan(layoutB.x, layoutA.x)
        XCTAssertGreaterThan(layoutC.width, layoutA.width)
    }

    func testSelectionGuideQuantizesToConfiguredStep() {
        let rawDate = makeDate(hour: 14, minute: 47)
        let guide15 = WeeklySelectionGuide.make(from: rawDate, calendar: calendar, slotMinutes: 15)
        XCTAssertEqual(guide15.minuteOfDay, 14 * 60 + 45)

        let guide30 = WeeklySelectionGuide.make(from: rawDate, calendar: calendar, slotMinutes: 30)
        XCTAssertEqual(guide30.minuteOfDay, 14 * 60 + 30)
    }
}
