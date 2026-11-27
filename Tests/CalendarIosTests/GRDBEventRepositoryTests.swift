import XCTest
@testable import CalendarIos

final class GRDBEventRepositoryTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        cal.firstWeekday = 2
        return cal
    }

    func testSeedIfNeededIsIdempotent() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBEventRepository(dbWriter: database.dbWriter, calendar: calendar)
        let referenceDate = Date(timeIntervalSince1970: 1_795_651_200) // 2026-11-26

        try await repository.seedIfNeeded(referenceDate: referenceDate)
        let firstTypes = try await repository.fetchEventTypes()
        XCTAssertEqual(firstTypes.count, 3)

        try await repository.seedIfNeeded(referenceDate: referenceDate)
        let secondTypes = try await repository.fetchEventTypes()
        XCTAssertEqual(secondTypes.count, 3)
    }

    func testUpsertFetchAndDeleteEvent() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBEventRepository(dbWriter: database.dbWriter, calendar: calendar)
        let start = Date(timeIntervalSince1970: 1_795_680_000)

        let draft = EventDraft(
            id: nil,
            eventTypeId: nil,
            customTitle: "Design review",
            customColorHex: 0xFF3A7AFE,
            startAt: start,
            durationMinutes: 45,
            reminderMinutes: 15,
            note: "Check iOS tab bar"
        )

        let created = try await repository.upsert(draft)
        XCTAssertGreaterThan(created.id, 0)
        XCTAssertEqual(created.title, "Design review")
        XCTAssertEqual(created.durationMinutes, 45)

        let interval = DateInterval(
            start: start.addingTimeInterval(-3600),
            end: start.addingTimeInterval(3600)
        )
        let fetched = try await repository.events(in: interval)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, created.id)

        var updatedDraft = EventDraft(event: created)
        updatedDraft.durationMinutes = 90
        updatedDraft.note = "Extended session"
        let updated = try await repository.upsert(updatedDraft)
        XCTAssertEqual(updated.id, created.id)
        XCTAssertEqual(updated.durationMinutes, 90)
        XCTAssertEqual(updated.note, "Extended session")

        try await repository.delete(id: created.id)
        let afterDelete = try await repository.events(in: interval)
        XCTAssertTrue(afterDelete.isEmpty)
    }
}
