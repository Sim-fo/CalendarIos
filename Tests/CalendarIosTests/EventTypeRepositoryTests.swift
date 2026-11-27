import XCTest
@testable import CalendarIos

final class EventTypeRepositoryTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        cal.firstWeekday = 2
        return cal
    }

    func testUpsertCountsAndUniquenessCheck() async throws {
        let database = try AppDatabase.inMemory()
        let repo = GRDBEventRepository(dbWriter: database.dbWriter, calendar: calendar)

        let created = try await repo.upsertEventType(
            EventTypeDraft(
                id: nil,
                title: "Deep Work",
                defaultDurationMinutes: 90,
                colorHex: 0xFF8FBDF5,
                notifyBeforeMinutes: 15
            )
        )
        XCTAssertGreaterThan(created.id, 0)

        let duplicate = try await repo.isEventTypeTitleUnique("deep work", excludingId: nil)
        XCTAssertFalse(duplicate)

        let sameExcludingSelf = try await repo.isEventTypeTitleUnique("Deep Work", excludingId: created.id)
        XCTAssertTrue(sameExcludingSelf)

        let start = Date(timeIntervalSince1970: 1_795_680_000)
        _ = try await repo.upsert(
            EventDraft(
                id: nil,
                eventTypeId: created.id,
                customTitle: "",
                customColorHex: nil,
                startAt: start,
                durationMinutes: 90,
                reminderMinutes: 15,
                note: ""
            )
        )

        let withCounts = try await repo.fetchEventTypesWithCounts()
        XCTAssertEqual(withCounts.count, 1)
        XCTAssertEqual(withCounts.first?.eventCount, 1)
    }

    func testDeleteTemplateWithAndWithoutLinkedEvents() async throws {
        let database = try AppDatabase.inMemory()
        let repo = GRDBEventRepository(dbWriter: database.dbWriter, calendar: calendar)
        let start = Date(timeIntervalSince1970: 1_795_680_000)
        let range = DateInterval(start: start.addingTimeInterval(-3600), end: start.addingTimeInterval(7200))

        let typeA = try await repo.upsertEventType(
            EventTypeDraft(id: nil, title: "A", defaultDurationMinutes: 60, colorHex: 0xFFE59494, notifyBeforeMinutes: 0)
        )
        let typeB = try await repo.upsertEventType(
            EventTypeDraft(id: nil, title: "B", defaultDurationMinutes: 60, colorHex: 0xFF99C79B, notifyBeforeMinutes: 0)
        )

        _ = try await repo.upsert(
            EventDraft(id: nil, eventTypeId: typeA.id, customTitle: "", customColorHex: nil, startAt: start, durationMinutes: 60, reminderMinutes: 0, note: "")
        )
        _ = try await repo.upsert(
            EventDraft(id: nil, eventTypeId: typeB.id, customTitle: "Keep me", customColorHex: nil, startAt: start.addingTimeInterval(1800), durationMinutes: 60, reminderMinutes: 0, note: "")
        )

        try await repo.deleteEventType(id: typeA.id, deleteLinkedEvents: true)
        var remaining = try await repo.events(in: range)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.eventTypeId, typeB.id)

        try await repo.deleteEventType(id: typeB.id, deleteLinkedEvents: false)
        remaining = try await repo.events(in: range)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertNil(remaining.first?.eventTypeId)
        XCTAssertEqual(remaining.first?.title, "Keep me")
    }

    func testNameGeneratorIncrementsCaseInsensitively() {
        let first = NameGenerator.generateNextName(existingNames: [])
        XCTAssertEqual(first, "NoName_01")

        let third = NameGenerator.generateNextName(existingNames: ["noname_01", "NoName_02"])
        XCTAssertEqual(third, "NoName_03")
    }
}
