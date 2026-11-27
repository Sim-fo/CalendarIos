import Foundation
import XCTest
@testable import CalendarIos

final class Stage3CalendarLogicTests: XCTestCase {
    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2
        return cal
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - DailyFreeTimeCalculator

    func testDailyFreeTimeInsertsBlocksOnlyAboveThresholdAndHandlesOverlaps() {
        let e1 = CalendarEvent(
            id: 1, eventTypeId: nil, customTitle: "Standup", customColorHex: nil,
            title: "Standup", colorHex: 0xFF5DADE2,
            startAt: makeDate(2026, 6, 10, 9, 0), durationMinutes: 30, reminderMinutes: -1, note: nil
        )
        // 15-minute gap (below 30-min threshold -> no free time block)
        let e2 = CalendarEvent(
            id: 2, eventTypeId: nil, customTitle: "Design", customColorHex: nil,
            title: "Design", colorHex: 0xFF5DADE2,
            startAt: makeDate(2026, 6, 10, 9, 45), durationMinutes: 90, reminderMinutes: -1, note: nil
        )
        // Overlaps with e2 (ends earlier at 10:30, so latestEnd must stay 11:15)
        let e3 = CalendarEvent(
            id: 3, eventTypeId: nil, customTitle: "Quick call", customColorHex: nil,
            title: "Quick call", colorHex: 0xFF5DADE2,
            startAt: makeDate(2026, 6, 10, 10, 0), durationMinutes: 30, reminderMinutes: -1, note: nil
        )
        // 75-minute gap from 11:15 to 12:30 (above threshold -> free time block!)
        let e4 = CalendarEvent(
            id: 4, eventTypeId: nil, customTitle: "Lunch", customColorHex: nil,
            title: "Lunch", colorHex: 0xFF5DADE2,
            startAt: makeDate(2026, 6, 10, 12, 30), durationMinutes: 60, reminderMinutes: -1, note: nil
        )

        let entries = DailyFreeTimeCalculator.buildSchedule(
            events: [e4, e2, e1, e3],
            thresholdMinutes: 30
        )

        XCTAssertEqual(entries.count, 5)
        if case .freeTime(let start, let end, let mins) = entries[3] {
            XCTAssertEqual(start, makeDate(2026, 6, 10, 11, 15))
            XCTAssertEqual(end, makeDate(2026, 6, 10, 12, 30))
            XCTAssertEqual(mins, 75)
        } else {
            XCTFail("Expected a 75-minute free time block at index 3")
        }
    }

    // MARK: - TrackerItem

    func testTrackerOverdueAndMarkerDaysCalculation() {
        let resetDate = makeDate(2026, 5, 1, 8, 0)
        let tracker = TrackerItem(
            id: 1,
            name: "Contact lenses",
            intervalDays: 14,
            createdDate: resetDate,
            lastResetDate: resetDate,
            colorHex: TrackerItem.defaultColorHex
        )

        XCTAssertFalse(tracker.isOverdue(referenceDate: makeDate(2026, 5, 14), calendar: utcCalendar))
        XCTAssertTrue(tracker.isOverdue(referenceDate: makeDate(2026, 5, 15), calendar: utcCalendar))
        XCTAssertEqual(tracker.daysSinceReset(referenceDate: makeDate(2026, 5, 15), calendar: utcCalendar), 14)

        let mayMarkers = tracker.markerDays(inYear: 2026, month: 5, calendar: utcCalendar)
        XCTAssertEqual(mayMarkers, Set([15, 29]))
        XCTAssertFalse(tracker.hasMarker(on: makeDate(2026, 5, 1), calendar: utcCalendar))
        XCTAssertTrue(tracker.hasMarker(on: makeDate(2026, 5, 15), calendar: utcCalendar))
        XCTAssertTrue(tracker.hasMarker(on: makeDate(2026, 5, 29), calendar: utcCalendar))
    }

    // MARK: - BirthdayItem

    func testBirthdayParsingLeapYearAndAge() {
        let leapBirthday = BirthdayItem(
            id: 1,
            name: "Alex",
            birthDate: "2000-02-29",
            note: nil,
            contactPhone: nil,
            contactId: nil,
            photoPath: nil,
            remindWeekBefore: true,
            remindAtStart: true,
            lastAcknowledgedYear: 2025
        )

        XCTAssertTrue(leapBirthday.hasBirthYear)
        XCTAssertEqual(leapBirthday.age(inYear: 2026), 26)
        XCTAssertTrue(leapBirthday.isAcknowledged(inYear: 2025))
        XCTAssertFalse(leapBirthday.isAcknowledged(inYear: 2026))

        // In non-leap year 2026, Feb 29 falls back to Feb 28
        XCTAssertTrue(leapBirthday.matches(date: makeDate(2026, 2, 28), calendar: utcCalendar))
        // In leap year 2028, Feb 29 stays Feb 29
        XCTAssertTrue(leapBirthday.matches(date: makeDate(2028, 2, 29), calendar: utcCalendar))

        let noYearBirthday = BirthdayItem(
            id: 2,
            name: "Sam",
            birthDate: BirthdayItem.formatISO(year: nil, month: 7, day: 14),
            note: nil,
            contactPhone: nil,
            contactId: nil,
            photoPath: nil,
            remindWeekBefore: false,
            remindAtStart: true,
            lastAcknowledgedYear: nil
        )
        XCTAssertEqual(noYearBirthday.birthDate, "--07-14")
        XCTAssertFalse(noYearBirthday.hasBirthYear)
        XCTAssertNil(noYearBirthday.age(inYear: 2026))
        XCTAssertTrue(noYearBirthday.matches(date: makeDate(2026, 7, 14), calendar: utcCalendar))
    }

    // MARK: - WeeklyEventInstanceGenerator

    func testWeeklyRecurringInstanceGeneration() {
        let weekly = WeeklyRecurringItem(
            id: 5,
            templateId: 10,
            customTitle: nil,
            customColorHex: nil,
            reminderMinutes: 15,
            slots: [
                WeeklyRecurringSlot(id: 1, weeklyEventId: 5, dayOfWeek: 1, startTime: "09:30", durationMinutes: 60, note: "Monday session", sortOrder: 0),
                WeeklyRecurringSlot(id: 2, weeklyEventId: 5, dayOfWeek: 3, startTime: "18:00", durationMinutes: 90, note: nil, sortOrder: 1)
            ]
        )
        let template = EventType(id: 10, title: "Gym", defaultDurationMinutes: 60, colorHex: 0xFF2ECC71, notifyBeforeMinutes: 10)

        // 2026-06-08 is a Monday; interval covers Mon..Sun
        let weekInterval = DateInterval(start: makeDate(2026, 6, 8, 0, 0), end: makeDate(2026, 6, 15, 0, 0))
        let instances = WeeklyEventInstanceGenerator.generateInstances(
            for: weekly,
            template: template,
            in: weekInterval,
            calendar: utcCalendar
        )

        XCTAssertEqual(instances.count, 2)
        XCTAssertTrue(instances.allSatisfy(\.isRecurringInstance))
        XCTAssertEqual(instances[0].title, "Gym")
        XCTAssertEqual(instances[0].startAt, makeDate(2026, 6, 8, 9, 30))
        XCTAssertEqual(instances[0].durationMinutes, 60)
        XCTAssertEqual(instances[1].startAt, makeDate(2026, 6, 10, 18, 0))
        XCTAssertEqual(instances[1].durationMinutes, 90)
    }
}
