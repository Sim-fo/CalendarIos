import Foundation
import GRDB

final class GRDBEventRepository: @unchecked Sendable, EventRepository, EventTypeRepository {
    private let dbWriter: DatabaseQueue
    private let calendar: Calendar

    init(dbWriter: DatabaseQueue, calendar: Calendar = .current) {
        self.dbWriter = dbWriter
        self.calendar = calendar
    }

    func fetchEventTypes() async throws -> [EventType] {
        try await dbWriter.read { db in
            try EventTypeRecord
                .all()
                .order(Column("title"))
                .fetchAll(db)
                .compactMap { $0.asDomain() }
        }
    }

    func events(in interval: DateInterval) async throws -> [CalendarEvent] {
        try await dbWriter.read { db in
            let records = try EventRecord
                .all()
                .filter(
                    sql: "startAtMillis >= ? AND startAtMillis < ?",
                    arguments: [interval.start.millisecondsSince1970, interval.end.millisecondsSince1970]
                )
                .order(Column("startAtMillis"))
                .fetchAll(db)

            let typeMap = try loadEventTypeMap(db: db)
            return records.map { record in
                makeDomainEvent(from: record, typeMap: typeMap)
            }
        }
    }

    func upsert(_ draft: EventDraft) async throws -> CalendarEvent {
        try await dbWriter.write { db in
            var record = EventRecord(
                id: draft.id,
                eventTypeId: draft.eventTypeId,
                customTitle: draft.customTitle.nilIfBlank,
                customColorHex: draft.customColorHex,
                startAtMillis: draft.startAt.millisecondsSince1970,
                durationMinutes: max(15, draft.durationMinutes),
                reminderMinutes: max(0, draft.reminderMinutes),
                note: draft.note.nilIfBlank,
                lastModifiedMillis: Date().millisecondsSince1970
            )
            try record.save(db)

            let typeMap = try loadEventTypeMap(db: db)
            return makeDomainEvent(from: record, typeMap: typeMap)
        }
    }

    func delete(id: Int64) async throws {
        _ = try await dbWriter.write { db in
            try EventRecord.deleteOne(db, key: id)
        }
    }

    func seedIfNeeded(referenceDate: Date) async throws {
        try await dbWriter.write { db in
            let existingCount = try EventRecord.fetchCount(db)
            if existingCount > 0 {
                return
            }

            let now = Date().millisecondsSince1970
            var focus = EventTypeRecord(
                id: nil,
                title: "Focus",
                defaultDurationMinutes: 90,
                colorHex: 0xFF3A7AFE,
                notifyBeforeMinutes: 10,
                lastModifiedMillis: now
            )
            var workout = EventTypeRecord(
                id: nil,
                title: "Workout",
                defaultDurationMinutes: 60,
                colorHex: 0xFF11A36A,
                notifyBeforeMinutes: 15,
                lastModifiedMillis: now
            )
            var call = EventTypeRecord(
                id: nil,
                title: "Call",
                defaultDurationMinutes: 30,
                colorHex: 0xFFEF6C3E,
                notifyBeforeMinutes: 5,
                lastModifiedMillis: now
            )

            try focus.save(db)
            try workout.save(db)
            try call.save(db)

            let weekStart = calendar.startOfWeek(containing: referenceDate)
            let mondayMorning = calendar.dateBySettingHour(9, minute: 0, on: weekStart)
            let tuesdayWorkout = calendar.dateBySettingHour(
                18,
                minute: 30,
                on: calendar.date(byAdding: .day, value: 1, to: weekStart) ?? weekStart
            )
            let fridayCall = calendar.dateBySettingHour(
                14,
                minute: 0,
                on: calendar.date(byAdding: .day, value: 4, to: weekStart) ?? weekStart
            )

            var records = [
                EventRecord(
                    id: nil,
                    eventTypeId: focus.id,
                    customTitle: "Weekly planning",
                    customColorHex: nil,
                    startAtMillis: mondayMorning.millisecondsSince1970,
                    durationMinutes: 90,
                    reminderMinutes: 10,
                    note: "Review priorities and unblock the week.",
                    lastModifiedMillis: now
                ),
                EventRecord(
                    id: nil,
                    eventTypeId: workout.id,
                    customTitle: nil,
                    customColorHex: nil,
                    startAtMillis: tuesdayWorkout.millisecondsSince1970,
                    durationMinutes: 60,
                    reminderMinutes: 15,
                    note: nil,
                    lastModifiedMillis: now
                ),
                EventRecord(
                    id: nil,
                    eventTypeId: call.id,
                    customTitle: "Client sync",
                    customColorHex: 0xFFD44C8D,
                    startAtMillis: fridayCall.millisecondsSince1970,
                    durationMinutes: 45,
                    reminderMinutes: 5,
                    note: "Discuss next sprint milestones.",
                    lastModifiedMillis: now
                )
            ]

            for index in records.indices {
                try records[index].save(db)
            }
        }
    }

    private func loadEventTypeMap(db: Database) throws -> [Int64: EventType] {
        let eventTypes = try EventTypeRecord
            .all()
            .fetchAll(db)
            .compactMap { $0.asDomain() }
        return Dictionary(uniqueKeysWithValues: eventTypes.map { ($0.id, $0) })
    }

    private func makeDomainEvent(from record: EventRecord, typeMap: [Int64: EventType]) -> CalendarEvent {
        let eventType = record.eventTypeId.flatMap { typeMap[$0] }
        let title = record.customTitle?.nilIfBlank ?? eventType?.title ?? "Untitled"
        let colorHex = record.customColorHex ?? eventType?.colorHex ?? CalendarColor.defaultEventHex

        return CalendarEvent(
            id: record.id ?? 0,
            eventTypeId: record.eventTypeId,
            customTitle: record.customTitle,
            customColorHex: record.customColorHex,
            title: title,
            colorHex: colorHex,
            startAt: Date(millisecondsSince1970: record.startAtMillis),
            durationMinutes: record.durationMinutes,
            reminderMinutes: record.reminderMinutes,
            note: record.note
        )
    }
}
