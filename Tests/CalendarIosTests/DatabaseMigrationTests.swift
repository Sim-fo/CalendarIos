import GRDB
import XCTest
@testable import CalendarIos

final class DatabaseMigrationTests: XCTestCase {
    func testInMemoryDatabaseCreatesExpectedTablesAndIndexes() throws {
        let database = try AppDatabase.inMemory()

        try database.dbWriter.read { db in
            XCTAssertTrue(try db.tableExists("event_types"))
            XCTAssertTrue(try db.tableExists("events"))

            let indexes = try db.indexes(on: "events").map(\.name)
            XCTAssertTrue(indexes.contains("idx_events_startAtMillis"))
            XCTAssertTrue(indexes.contains("idx_events_eventTypeId"))
        }
    }

    func testDeletingEventTypeNullifiesEventForeignKey() throws {
        let database = try AppDatabase.inMemory()
        let now = Date().millisecondsSince1970

        try database.dbWriter.write { db in
            var eventType = EventTypeRecord(
                id: nil,
                title: "Workout",
                defaultDurationMinutes: 60,
                colorHex: 0xFF11A36A,
                notifyBeforeMinutes: 10,
                lastModifiedMillis: now
            )
            try eventType.save(db)

            var event = EventRecord(
                id: nil,
                eventTypeId: eventType.id,
                customTitle: "Leg day",
                customColorHex: nil,
                startAtMillis: now,
                durationMinutes: 60,
                reminderMinutes: 10,
                note: nil,
                lastModifiedMillis: now
            )
            try event.save(db)

            try eventType.delete(db)

            let fetched = try EventRecord.fetchOne(db, key: event.id)
            XCTAssertNotNil(fetched)
            XCTAssertNil(fetched?.eventTypeId)
        }
    }
}
