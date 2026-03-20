import Foundation
import GRDB

enum DatabaseMigratorFactory {
    static func make() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = false
        #endif

        migrator.registerMigration("v1_event_types_and_events") { db in
            try db.create(table: "event_types") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("title", .text).notNull()
                table.column("defaultDurationMinutes", .integer).notNull()
                table.column("colorHex", .integer).notNull()
                table.column("notifyBeforeMinutes", .integer).notNull()
                table.column("lastModifiedMillis", .integer).notNull()
            }

            try db.create(table: "events") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("eventTypeId", .integer)
                    .references("event_types", onDelete: .setNull)
                table.column("customTitle", .text)
                table.column("customColorHex", .integer)
                table.column("startAtMillis", .integer).notNull()
                table.column("durationMinutes", .integer).notNull()
                table.column("reminderMinutes", .integer).notNull()
                table.column("note", .text)
                table.column("lastModifiedMillis", .integer).notNull()
            }

            try db.create(index: "idx_events_startAtMillis", on: "events", columns: ["startAtMillis"])
            try db.create(index: "idx_events_eventTypeId", on: "events", columns: ["eventTypeId"])
        }

        return migrator
    }
}

