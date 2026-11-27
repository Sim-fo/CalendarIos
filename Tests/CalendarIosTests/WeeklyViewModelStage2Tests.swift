import XCTest
@testable import CalendarIos

@MainActor
final class WeeklyViewModelStage2Tests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        cal.firstWeekday = 2
        return cal
    }

    private func makeDate(day: Int, hour: Int, minute: Int = 0) -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 11,
            day: day,
            hour: hour,
            minute: minute
        )
        return calendar.date(from: components)!
    }

    func testLongPressOpensCreateChooserAndCopyModeDuplicatesEvent() async throws {
        let database = try AppDatabase.inMemory()
        let repo = GRDBEventRepository(dbWriter: database.dbWriter, calendar: calendar)
        let refDate = makeDate(day: 26, hour: 9)

        let template = try await repo.upsertEventType(
            EventTypeDraft(id: nil, title: "Gym", defaultDurationMinutes: 75, colorHex: 0xFF99C79B, notifyBeforeMinutes: 10)
        )
        let vm = WeeklyViewModel(
            eventRepository: repo,
            eventTypeRepository: repo,
            calendar: calendar,
            referenceDate: refDate
        )
        await vm.loadInitialState()

        // 1. Normal long-press commit opens EventCreate chooser quantized to 15 min
        let rawTapDate = makeDate(day: 26, hour: 10, minute: 22)
        vm.handleLongPressCommit(at: rawTapDate, quantizationMinutes: 15)
        XCTAssertEqual(vm.activeSheet, .createChooser(makeDate(day: 26, hour: 10, minute: 15)))

        // 2. Selecting template creates event immediately
        vm.createEvent(at: makeDate(day: 26, hour: 10, minute: 15), using: template)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertNil(vm.activeSheet)

        let allEventsAfterCreate = vm.sections.flatMap(\.events)
        let created = try XCTUnwrap(allEventsAfterCreate.first { $0.eventTypeId == template.id })
        XCTAssertEqual(created.durationMinutes, 75)

        // 3. Copy mode disables long-press until an event is selected
        vm.toggleCopyMode()
        XCTAssertTrue(vm.isCopyModeEnabled)
        XCTAssertFalse(vm.isLongPressEnabled)

        vm.handleEventTap(created)
        XCTAssertEqual(vm.selectedCopyEvent?.id, created.id)
        XCTAssertTrue(vm.isLongPressEnabled)

        // 4. Long-press commit in Copy Mode copies event instead of opening sheet
        let targetDate = makeDate(day: 27, hour: 14, minute: 40)
        vm.handleLongPressCommit(at: targetDate, quantizationMinutes: 30)
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertNil(vm.activeSheet)
        let gymEvents = vm.sections.flatMap(\.events).filter { $0.eventTypeId == template.id }
        XCTAssertEqual(gymEvents.count, 2)
        XCTAssertTrue(gymEvents.contains { $0.startAt == makeDate(day: 27, hour: 14, minute: 30) })
    }
}
