import Foundation
import GRDB
import SwiftUI
import UniformTypeIdentifiers

struct CalendarBackupPayload: Codable, Sendable {
    var schemaVersion: Int = 2
    var exportedAtMillis: Int64
    var eventTypes: [EventTypeRecord]
    var events: [EventRecord]
    var todoItems: [TodoRecord]
    var trackers: [TrackerRecord]
    var birthdays: [BirthdayRecord]
    var weeklyRecurringEvents: [WeeklyRecurringEventRecord]
    var weeklyRecurringEventSlots: [WeeklyRecurringEventSlotRecord]
    var clients: [ClientRecord]
    var locationLinks: [LocationLinkRecord]
    var options: [OptionRecord]
    var optionFields: [OptionFieldRecord]
    var eventOptionValues: [EventOptionValueRecord]
}

struct BackupSummary: Equatable, Sendable {
    let eventCount: Int
    let templateCount: Int
    let todoCount: Int
    let trackerCount: Int
    let birthdayCount: Int
    let weeklyRecurringCount: Int
    let clientCount: Int
    let locationCount: Int
}

final class BackupService: @unchecked Sendable {
    private let dbWriter: DatabaseQueue

    init(dbWriter: DatabaseQueue) {
        self.dbWriter = dbWriter
    }

    func fetchSummary() async throws -> BackupSummary {
        try await dbWriter.read { db in
            BackupSummary(
                eventCount: try EventRecord.fetchCount(db),
                templateCount: try EventTypeRecord.fetchCount(db),
                todoCount: try TodoRecord.fetchCount(db),
                trackerCount: try TrackerRecord.fetchCount(db),
                birthdayCount: try BirthdayRecord.fetchCount(db),
                weeklyRecurringCount: try WeeklyRecurringEventRecord.fetchCount(db),
                clientCount: try ClientRecord.fetchCount(db),
                locationCount: try LocationLinkRecord.fetchCount(db)
            )
        }
    }

    func exportJSONData() async throws -> Data {
        let payload: CalendarBackupPayload = try await dbWriter.read { db in
            CalendarBackupPayload(
                schemaVersion: 2,
                exportedAtMillis: Date().millisecondsSince1970,
                eventTypes: try EventTypeRecord.fetchAll(db),
                events: try EventRecord.fetchAll(db),
                todoItems: try TodoRecord.fetchAll(db),
                trackers: try TrackerRecord.fetchAll(db),
                birthdays: try BirthdayRecord.fetchAll(db),
                weeklyRecurringEvents: try WeeklyRecurringEventRecord.fetchAll(db),
                weeklyRecurringEventSlots: try WeeklyRecurringEventSlotRecord.fetchAll(db),
                clients: try ClientRecord.fetchAll(db),
                locationLinks: try LocationLinkRecord.fetchAll(db),
                options: try OptionRecord.fetchAll(db),
                optionFields: try OptionFieldRecord.fetchAll(db),
                eventOptionValues: try EventOptionValueRecord.fetchAll(db)
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    func importJSONData(_ data: Data) async throws {
        let decoder = JSONDecoder()
        let payload = try decoder.decode(CalendarBackupPayload.self, from: data)

        try await dbWriter.write { db in
            // Delete in reverse foreign-key order
            try db.execute(sql: "DELETE FROM event_option_values")
            try db.execute(sql: "DELETE FROM option_fields")
            try db.execute(sql: "DELETE FROM options")
            try db.execute(sql: "DELETE FROM weekly_recurring_event_slots")
            try db.execute(sql: "DELETE FROM weekly_recurring_events")
            try db.execute(sql: "DELETE FROM events")
            try db.execute(sql: "DELETE FROM event_types")
            try db.execute(sql: "DELETE FROM todo_items")
            try db.execute(sql: "DELETE FROM trackers")
            try db.execute(sql: "DELETE FROM birthdays")
            try db.execute(sql: "DELETE FROM clients")
            try db.execute(sql: "DELETE FROM location_links")

            // Insert parents before children to satisfy foreign keys
            for var item in payload.eventTypes { try item.insert(db) }
            for var item in payload.clients { try item.insert(db) }
            for var item in payload.locationLinks { try item.insert(db) }
            for var item in payload.events { try item.insert(db) }
            for var item in payload.todoItems { try item.insert(db) }
            for var item in payload.trackers { try item.insert(db) }
            for var item in payload.birthdays { try item.insert(db) }
            for var item in payload.weeklyRecurringEvents { try item.insert(db) }
            for var item in payload.weeklyRecurringEventSlots { try item.insert(db) }
            for var item in payload.options { try item.insert(db) }
            for var item in payload.optionFields { try item.insert(db) }
            for var item in payload.eventOptionValues { try item.insert(db) }
        }

        NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
    }
}

struct JSONBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
