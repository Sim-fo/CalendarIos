import Foundation
import GRDB

final class GRDBEventRepository: @unchecked Sendable, EventRepository, EventTypeRepository {
    private let dbWriter: DatabaseQueue
    private let calendar: Calendar

    init(dbWriter: DatabaseQueue, calendar: Calendar = .current) {
        self.dbWriter = dbWriter
        self.calendar = calendar
    }

    // MARK: - EventTypeRepository

    func fetchEventTypes() async throws -> [EventType] {
        try await dbWriter.read { db in
            try EventTypeRecord
                .all()
                .order(Column("title").collating(.localizedCaseInsensitiveCompare))
                .fetchAll(db)
                .compactMap { $0.asDomain() }
        }
    }

    func fetchEventTypesWithCounts() async throws -> [EventTypeWithCount] {
        try await dbWriter.read { db in
            let types = try EventTypeRecord
                .all()
                .order(Column("title").collating(.localizedCaseInsensitiveCompare))
                .fetchAll(db)
                .compactMap { $0.asDomain() }

            let countRows = try Row.fetchAll(
                db,
                sql: "SELECT eventTypeId, COUNT(*) AS cnt FROM events WHERE eventTypeId IS NOT NULL GROUP BY eventTypeId"
            )
            var countsById: [Int64: Int] = [:]
            for row in countRows {
                if let typeId: Int64 = row["eventTypeId"], let count: Int = row["cnt"] {
                    countsById[typeId] = count
                }
            }

            return types.map { type in
                EventTypeWithCount(eventType: type, eventCount: countsById[type.id, default: 0])
            }
        }
    }

    func fetchEventType(id: Int64) async throws -> EventType? {
        try await dbWriter.read { db in
            try EventTypeRecord.fetchOne(db, key: id)?.asDomain()
        }
    }

    func upsertEventType(_ draft: EventTypeDraft) async throws -> EventType {
        try await dbWriter.write { db in
            let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            var record = EventTypeRecord(
                id: draft.id,
                title: trimmedTitle,
                defaultDurationMinutes: max(1, draft.defaultDurationMinutes),
                colorHex: CalendarColor.opaqueHex(draft.colorHex),
                notifyBeforeMinutes: max(0, draft.notifyBeforeMinutes),
                lastModifiedMillis: Date().millisecondsSince1970
            )
            try record.save(db)
            return EventType(
                id: record.id ?? 0,
                title: record.title,
                defaultDurationMinutes: record.defaultDurationMinutes,
                colorHex: record.colorHex,
                notifyBeforeMinutes: record.notifyBeforeMinutes
            )
        }
    }

    func deleteEventType(id: Int64, deleteLinkedEvents: Bool) async throws {
        try await dbWriter.write { db in
            if deleteLinkedEvents {
                try db.execute(
                    sql: "DELETE FROM events WHERE eventTypeId = ?",
                    arguments: [id]
                )
            }
            _ = try EventTypeRecord.deleteOne(db, key: id)
        }
    }

    func isEventTypeTitleUnique(_ title: String, excludingId: Int64?) async throws -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        return try await dbWriter.read { db in
            let existing = try EventTypeRecord.fetchAll(db)
            return !existing.contains { record in
                if let excludingId, record.id == excludingId {
                    return false
                }
                return record.title.compare(trimmed, options: .caseInsensitive) == .orderedSame
            }
        }
    }

    // MARK: - EventRepository

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
            var allEvents = records.map { record in
                makeDomainEvent(from: record, typeMap: typeMap)
            }

            // Merge virtual weekly recurring event instances seamlessly
            let weeklyParents = try WeeklyRecurringEventRecord.fetchAll(db)
            if !weeklyParents.isEmpty {
                let allSlots = try WeeklyRecurringEventSlotRecord
                    .order(Column("sortOrder").asc, Column("dayOfWeek").asc, Column("startTime").asc)
                    .fetchAll(db)
                    .compactMap { $0.asDomain() }
                let slotsByParent = Dictionary(grouping: allSlots, by: \.weeklyEventId)

                for parent in weeklyParents {
                    guard let parentId = parent.id else { continue }
                    let item = WeeklyRecurringItem(
                        id: parentId,
                        templateId: parent.templateId,
                        customTitle: parent.customTitle,
                        customColorHex: parent.customColorHex,
                        reminderMinutes: parent.reminderMinutes,
                        slots: slotsByParent[parentId, default: []]
                    )
                    let template = parent.templateId.flatMap { typeMap[$0] }
                    let instances = WeeklyEventInstanceGenerator.generateInstances(
                        for: item,
                        template: template,
                        in: interval,
                        calendar: calendar
                    )
                    allEvents.append(contentsOf: instances)
                }
            }

            return allEvents.sorted { lhs, rhs in
                if lhs.startAt == rhs.startAt {
                    return lhs.id < rhs.id
                }
                return lhs.startAt < rhs.startAt
            }
        }
    }

    func fetchEvent(id: Int64) async throws -> CalendarEvent? {
        try await dbWriter.read { db in
            guard let record = try EventRecord.fetchOne(db, key: id) else { return nil }
            let typeMap = try loadEventTypeMap(db: db)
            return makeDomainEvent(from: record, typeMap: typeMap)
        }
    }

    func fetchUniqueEventTitles() async throws -> [String] {
        try await dbWriter.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT customTitle FROM events WHERE customTitle IS NOT NULL AND TRIM(customTitle) != ''"
            )
        }
    }

    func upsert(_ draft: EventDraft) async throws -> CalendarEvent {
        try await dbWriter.write { db in
            var record = EventRecord(
                id: draft.id,
                eventTypeId: draft.eventTypeId,
                customTitle: draft.customTitle.nilIfBlank,
                customColorHex: draft.customColorHex.map(CalendarColor.opaqueHex),
                startAtMillis: draft.startAt.millisecondsSince1970,
                durationMinutes: max(1, draft.durationMinutes),
                reminderMinutes: max(0, draft.reminderMinutes),
                note: draft.note.nilIfBlank,
                audioNotePath: draft.audioNotePath?.nilIfBlank,
                selectedOptionId: draft.selectedOptionId,
                selectedOptionName: draft.selectedOptionName?.nilIfBlank,
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
            let existingEvents = try EventRecord.fetchCount(db)
            let existingTypes = try EventTypeRecord.fetchCount(db)
            if existingEvents > 0 || existingTypes > 0 {
                return
            }

            let now = Date().millisecondsSince1970
            var focus = EventTypeRecord(
                id: nil,
                title: "Focus",
                defaultDurationMinutes: 90,
                colorHex: 0xFF8FBDF5,
                notifyBeforeMinutes: 10,
                lastModifiedMillis: now
            )
            var workout = EventTypeRecord(
                id: nil,
                title: "Workout",
                defaultDurationMinutes: 60,
                colorHex: 0xFF99C79B,
                notifyBeforeMinutes: 15,
                lastModifiedMillis: now
            )
            var call = EventTypeRecord(
                id: nil,
                title: "Call",
                defaultDurationMinutes: 30,
                colorHex: 0xFFFFBF80,
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
                    customTitle: nil,
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
                    eventTypeId: nil,
                    customTitle: "Client sync",
                    customColorHex: 0xFFEF8DAB,
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
            note: record.note,
            audioNotePath: record.audioNotePath,
            selectedOptionId: record.selectedOptionId,
            selectedOptionName: record.selectedOptionName
        )
    }
}
