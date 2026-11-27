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

        migrator.registerMigration("v2_full_calendar_schema") { db in
            // Extend events table for audio notes & selected template option
            try db.alter(table: "events") { table in
                table.add(column: "audioNotePath", .text)
                table.add(column: "selectedOptionId", .integer)
                table.add(column: "selectedOptionName", .text)
            }

            // Todo items
            try db.create(table: "todo_items") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("text", .text).notNull()
                table.column("isDone", .boolean).notNull().defaults(to: false)
                table.column("createdAtMillis", .integer).notNull()
                table.column("lastModifiedMillis", .integer).notNull()
            }

            // Trackers (periodic events)
            try db.create(table: "trackers") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("name", .text).notNull()
                table.column("intervalDays", .integer).notNull()
                table.column("createdDateMillis", .integer).notNull()
                table.column("lastResetDateMillis", .integer).notNull()
                table.column("colorHex", .integer).notNull()
                table.column("lastModifiedMillis", .integer).notNull()
            }

            // Birthdays
            try db.create(table: "birthdays") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("name", .text).notNull()
                table.column("birthDate", .text).notNull() // YYYY-MM-DD or --MM-DD
                table.column("note", .text)
                table.column("contactPhone", .text)
                table.column("contactId", .text)
                table.column("photoPath", .text)
                table.column("remindWeekBefore", .boolean).notNull().defaults(to: false)
                table.column("remindAtStart", .boolean).notNull().defaults(to: true)
                table.column("lastAcknowledgedYear", .integer)
                table.column("lastModifiedMillis", .integer).notNull()
            }

            // Weekly recurring events & multi-slot schedule
            try db.create(table: "weekly_recurring_events") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("templateId", .integer)
                    .references("event_types", onDelete: .setNull)
                table.column("customTitle", .text)
                table.column("customColorHex", .integer)
                table.column("reminderMinutes", .integer).notNull().defaults(to: 0)
                table.column("lastModifiedMillis", .integer).notNull()
            }

            try db.create(table: "weekly_recurring_event_slots") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("weeklyEventId", .integer)
                    .notNull()
                    .references("weekly_recurring_events", onDelete: .cascade)
                table.column("dayOfWeek", .integer).notNull() // ISO 1=Mon ... 7=Sun
                table.column("startTime", .text).notNull()    // HH:mm
                table.column("durationMinutes", .integer).notNull()
                table.column("note", .text)
                table.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
            try db.create(index: "idx_weekly_slots_eventId", on: "weekly_recurring_event_slots", columns: ["weeklyEventId"])

            // Clients
            try db.create(table: "clients") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("name", .text).notNull()
                table.column("phone", .text)
                table.column("email", .text)
                table.column("contactId", .text)
                table.column("photoPath", .text)
                table.column("note", .text)
                table.column("lastModifiedMillis", .integer).notNull()
            }

            // Map markers (location links)
            try db.create(table: "location_links") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("url", .text).notNull()
                table.column("title", .text)
                table.column("type", .text)
                table.column("lastModifiedMillis", .integer).notNull()
            }

            // Template options & option fields
            try db.create(table: "options") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("eventTypeId", .integer)
                    .notNull()
                    .references("event_types", onDelete: .cascade)
                table.column("name", .text).notNull()
                table.column("description", .text)
                table.column("lastModifiedMillis", .integer).notNull()
            }
            try db.create(index: "idx_options_eventTypeId", on: "options", columns: ["eventTypeId"])

            try db.create(table: "option_fields") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("optionId", .integer)
                    .notNull()
                    .references("options", onDelete: .cascade)
                table.column("fieldType", .text).notNull()
                table.column("sortOrder", .integer).notNull().defaults(to: 0)
                table.column("label", .text)
                table.column("defaultDurationMinutes", .integer)
                table.column("defaultTextValue", .text)
                table.column("defaultLocationId", .integer)
                table.column("photoPath", .text)
                table.column("lastModifiedMillis", .integer).notNull()
            }
            try db.create(index: "idx_option_fields_optionId", on: "option_fields", columns: ["optionId"])

            // Event option field values
            try db.create(table: "event_option_values") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("eventId", .integer)
                    .notNull()
                    .references("events", onDelete: .cascade)
                table.column("fieldId", .integer)
                    .notNull()
                    .references("option_fields", onDelete: .cascade)
                table.column("textValue", .text)
                table.column("photoPath", .text)
                table.column("clientId", .integer)
                    .references("clients", onDelete: .setNull)
                table.column("latitude", .double)
                table.column("longitude", .double)
                table.column("locationLabel", .text)
            }
            try db.create(index: "idx_event_option_values_eventId", on: "event_option_values", columns: ["eventId"])
            try db.create(index: "idx_event_option_values_fieldId", on: "event_option_values", columns: ["fieldId"])
        }

        return migrator
    }
}
