import Foundation
import GRDB

final class GRDBFeatureRepository:
    @unchecked Sendable,
    TodoRepository,
    TrackerRepository,
    BirthdayRepository,
    WeeklyRecurringRepository,
    ClientRepository,
    LocationLinkRepository,
    OptionRepository
{
    private let dbWriter: DatabaseQueue

    init(dbWriter: DatabaseQueue) {
        self.dbWriter = dbWriter
    }

    // MARK: - TodoRepository

    func fetchTodos() async throws -> [TodoItem] {
        try await dbWriter.read { db in
            try TodoRecord
                .order(Column("isDone").asc, Column("createdAtMillis").desc)
                .fetchAll(db)
                .compactMap { $0.asDomain() }
        }
    }

    func upsertTodo(id: Int64?, text: String, isDone: Bool) async throws -> TodoItem {
        try await dbWriter.write { db in
            let now = Date().millisecondsSince1970
            let existingCreated = try id.flatMap { try TodoRecord.fetchOne(db, key: $0)?.createdAtMillis } ?? now
            var record = TodoRecord(
                id: id,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                isDone: isDone,
                createdAtMillis: existingCreated,
                lastModifiedMillis: now
            )
            try record.save(db)
            return record.asDomain() ?? TodoItem(id: 0, text: record.text, isDone: isDone, createdAt: Date())
        }
    }

    func deleteTodo(id: Int64) async throws {
        _ = try await dbWriter.write { db in
            try TodoRecord.deleteOne(db, key: id)
        }
    }

    // MARK: - TrackerRepository

    func fetchTrackers() async throws -> [TrackerItem] {
        try await dbWriter.read { db in
            try TrackerRecord
                .order(Column("name").collating(.localizedCaseInsensitiveCompare))
                .fetchAll(db)
                .compactMap { $0.asDomain() }
        }
    }

    func upsertTracker(
        id: Int64?,
        name: String,
        intervalDays: Int,
        createdDate: Date,
        lastResetDate: Date,
        colorHex: Int
    ) async throws -> TrackerItem {
        try await dbWriter.write { db in
            var record = TrackerRecord(
                id: id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                intervalDays: max(1, intervalDays),
                createdDateMillis: createdDate.millisecondsSince1970,
                lastResetDateMillis: lastResetDate.millisecondsSince1970,
                colorHex: CalendarColor.opaqueHex(colorHex),
                lastModifiedMillis: Date().millisecondsSince1970
            )
            try record.save(db)
            return record.asDomain()!
        }
    }

    func resetTracker(id: Int64, at date: Date) async throws {
        try await dbWriter.write { db in
            guard var record = try TrackerRecord.fetchOne(db, key: id) else { return }
            record.lastResetDateMillis = date.millisecondsSince1970
            record.lastModifiedMillis = Date().millisecondsSince1970
            try record.save(db)
        }
    }

    func deleteTracker(id: Int64) async throws {
        _ = try await dbWriter.write { db in
            try TrackerRecord.deleteOne(db, key: id)
        }
    }

    func isTrackerNameUnique(_ name: String, excludingId: Int64?) async throws -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return try await dbWriter.read { db in
            let all = try TrackerRecord.fetchAll(db)
            return !all.contains { rec in
                if let excludingId, rec.id == excludingId { return false }
                return rec.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
            }
        }
    }

    // MARK: - BirthdayRepository

    func fetchBirthdays() async throws -> [BirthdayItem] {
        try await dbWriter.read { db in
            try BirthdayRecord
                .order(Column("name").collating(.localizedCaseInsensitiveCompare))
                .fetchAll(db)
                .compactMap { $0.asDomain() }
        }
    }

    func upsertBirthday(_ item: BirthdayItem, isNew: Bool) async throws -> BirthdayItem {
        try await dbWriter.write { db in
            var record = BirthdayRecord(
                id: isNew ? nil : item.id,
                name: item.name.trimmingCharacters(in: .whitespacesAndNewlines),
                birthDate: item.birthDate,
                note: item.note?.nilIfBlank,
                contactPhone: item.contactPhone?.nilIfBlank,
                contactId: item.contactId?.nilIfBlank,
                photoPath: item.photoPath?.nilIfBlank,
                remindWeekBefore: item.remindWeekBefore,
                remindAtStart: item.remindAtStart,
                lastAcknowledgedYear: item.lastAcknowledgedYear,
                lastModifiedMillis: Date().millisecondsSince1970
            )
            try record.save(db)
            return record.asDomain()!
        }
    }

    func acknowledgeBirthday(id: Int64, year: Int?) async throws {
        try await dbWriter.write { db in
            guard var record = try BirthdayRecord.fetchOne(db, key: id) else { return }
            record.lastAcknowledgedYear = year
            record.lastModifiedMillis = Date().millisecondsSince1970
            try record.save(db)
        }
    }

    func deleteBirthday(id: Int64) async throws {
        _ = try await dbWriter.write { db in
            try BirthdayRecord.deleteOne(db, key: id)
        }
    }

    // MARK: - WeeklyRecurringRepository

    func fetchWeeklyEvents() async throws -> [WeeklyRecurringItem] {
        try await dbWriter.read { db in
            let parents = try WeeklyRecurringEventRecord
                .order(Column("id").desc)
                .fetchAll(db)
            let allSlots = try WeeklyRecurringEventSlotRecord
                .order(Column("sortOrder").asc, Column("dayOfWeek").asc, Column("startTime").asc)
                .fetchAll(db)
                .compactMap { $0.asDomain() }
            let slotsByParent = Dictionary(grouping: allSlots, by: \.weeklyEventId)

            return parents.compactMap { rec -> WeeklyRecurringItem? in
                guard let id = rec.id else { return nil }
                return WeeklyRecurringItem(
                    id: id,
                    templateId: rec.templateId,
                    customTitle: rec.customTitle,
                    customColorHex: rec.customColorHex,
                    reminderMinutes: rec.reminderMinutes,
                    slots: slotsByParent[id, default: []]
                )
            }
        }
    }

    func fetchWeeklyEvent(id: Int64) async throws -> WeeklyRecurringItem? {
        try await dbWriter.read { db in
            guard let rec = try WeeklyRecurringEventRecord.fetchOne(db, key: id),
                  let parentId = rec.id else { return nil }
            let slots = try WeeklyRecurringEventSlotRecord
                .filter(Column("weeklyEventId") == parentId)
                .order(Column("sortOrder").asc, Column("dayOfWeek").asc, Column("startTime").asc)
                .fetchAll(db)
                .compactMap { $0.asDomain() }

            return WeeklyRecurringItem(
                id: parentId,
                templateId: rec.templateId,
                customTitle: rec.customTitle,
                customColorHex: rec.customColorHex,
                reminderMinutes: rec.reminderMinutes,
                slots: slots
            )
        }
    }

    func upsertWeeklyEvent(
        id: Int64?,
        templateId: Int64?,
        customTitle: String?,
        customColorHex: Int?,
        reminderMinutes: Int,
        slots: [WeeklyRecurringSlot]
    ) async throws -> WeeklyRecurringItem {
        try await dbWriter.write { db in
            var parent = WeeklyRecurringEventRecord(
                id: id,
                templateId: templateId,
                customTitle: customTitle?.nilIfBlank,
                customColorHex: customColorHex.map(CalendarColor.opaqueHex),
                reminderMinutes: max(0, reminderMinutes),
                lastModifiedMillis: Date().millisecondsSince1970
            )
            try parent.save(db)
            let parentId = parent.id ?? 0

            try db.execute(
                sql: "DELETE FROM weekly_recurring_event_slots WHERE weeklyEventId = ?",
                arguments: [parentId]
            )

            var savedSlots: [WeeklyRecurringSlot] = []
            for (index, slot) in slots.enumerated() {
                var slotRecord = WeeklyRecurringEventSlotRecord(
                    id: nil,
                    weeklyEventId: parentId,
                    dayOfWeek: min(max(slot.dayOfWeek, 1), 7),
                    startTime: slot.startTime,
                    durationMinutes: max(1, slot.durationMinutes),
                    note: slot.note?.nilIfBlank,
                    sortOrder: index
                )
                try slotRecord.save(db)
                if let domain = slotRecord.asDomain() {
                    savedSlots.append(domain)
                }
            }

            return WeeklyRecurringItem(
                id: parentId,
                templateId: parent.templateId,
                customTitle: parent.customTitle,
                customColorHex: parent.customColorHex,
                reminderMinutes: parent.reminderMinutes,
                slots: savedSlots
            )
        }
    }

    func deleteWeeklyEvent(id: Int64) async throws {
        _ = try await dbWriter.write { db in
            try WeeklyRecurringEventRecord.deleteOne(db, key: id)
        }
    }

    // MARK: - ClientRepository

    func fetchClients() async throws -> [ClientItem] {
        try await dbWriter.read { db in
            try ClientRecord
                .order(Column("name").collating(.localizedCaseInsensitiveCompare))
                .fetchAll(db)
                .compactMap { $0.asDomain() }
        }
    }

    func upsertClient(_ item: ClientItem, isNew: Bool) async throws -> ClientItem {
        try await dbWriter.write { db in
            var record = ClientRecord(
                id: isNew ? nil : item.id,
                name: item.name.trimmingCharacters(in: .whitespacesAndNewlines),
                phone: item.phone?.nilIfBlank,
                email: item.email?.nilIfBlank,
                contactId: item.contactId?.nilIfBlank,
                photoPath: item.photoPath?.nilIfBlank,
                note: item.note?.nilIfBlank,
                lastModifiedMillis: Date().millisecondsSince1970
            )
            try record.save(db)
            return record.asDomain()!
        }
    }

    func deleteClient(id: Int64) async throws {
        _ = try await dbWriter.write { db in
            try ClientRecord.deleteOne(db, key: id)
        }
    }

    // MARK: - LocationLinkRepository

    func fetchLocationLinks() async throws -> [LocationLinkItem] {
        try await dbWriter.read { db in
            try LocationLinkRecord
                .order(Column("id").desc)
                .fetchAll(db)
                .compactMap { $0.asDomain() }
        }
    }

    func upsertLocationLink(id: Int64?, url: String, title: String?, type: String?) async throws -> LocationLinkItem {
        try await dbWriter.write { db in
            var record = LocationLinkRecord(
                id: id,
                url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                title: title?.nilIfBlank,
                type: type?.nilIfBlank,
                lastModifiedMillis: Date().millisecondsSince1970
            )
            try record.save(db)
            return record.asDomain()!
        }
    }

    func deleteLocationLink(id: Int64) async throws {
        _ = try await dbWriter.write { db in
            try LocationLinkRecord.deleteOne(db, key: id)
        }
    }

    // MARK: - OptionRepository

    func fetchOptions(forEventTypeId eventTypeId: Int64) async throws -> [TemplateOption] {
        try await dbWriter.read { db in
            let options = try OptionRecord
                .filter(Column("eventTypeId") == eventTypeId)
                .order(Column("id").asc)
                .fetchAll(db)
            let optionIds = options.compactMap(\.id)
            guard !optionIds.isEmpty else { return [] }

            let allFields = try OptionFieldRecord
                .filter(optionIds.contains(Column("optionId")))
                .order(Column("sortOrder").asc, Column("id").asc)
                .fetchAll(db)
                .compactMap { $0.asDomain() }
            let fieldsByOption = Dictionary(grouping: allFields, by: \.optionId)

            return options.compactMap { rec -> TemplateOption? in
                guard let id = rec.id else { return nil }
                return TemplateOption(
                    id: id,
                    eventTypeId: rec.eventTypeId,
                    name: rec.name,
                    description: rec.description,
                    fields: fieldsByOption[id, default: []]
                )
            }
        }
    }

    func upsertOption(
        id: Int64?,
        eventTypeId: Int64,
        name: String,
        description: String?,
        fields: [OptionField]
    ) async throws -> TemplateOption {
        try await dbWriter.write { db in
            let now = Date().millisecondsSince1970
            var optionRec = OptionRecord(
                id: id,
                eventTypeId: eventTypeId,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description?.nilIfBlank,
                lastModifiedMillis: now
            )
            try optionRec.save(db)
            let optionId = optionRec.id ?? 0

            // Sync option fields while keeping existing IDs when updating to preserve event_option_values
            let existingFields = try OptionFieldRecord
                .filter(Column("optionId") == optionId)
                .fetchAll(db)
            let incomingIds = Set(fields.map(\.id).filter { $0 > 0 })
            for oldField in existingFields {
                if let oldId = oldField.id, !incomingIds.contains(oldId) {
                    _ = try OptionFieldRecord.deleteOne(db, key: oldId)
                }
            }

            var savedFields: [OptionField] = []
            for (index, field) in fields.prefix(5).enumerated() {
                var fieldRec = OptionFieldRecord(
                    id: field.id > 0 ? field.id : nil,
                    optionId: optionId,
                    fieldType: field.fieldType.rawValue,
                    sortOrder: index,
                    label: field.label?.nilIfBlank,
                    defaultDurationMinutes: field.defaultDurationMinutes,
                    defaultTextValue: field.defaultTextValue?.nilIfBlank,
                    defaultLocationId: field.defaultLocationId,
                    photoPath: field.photoPath?.nilIfBlank,
                    lastModifiedMillis: now
                )
                try fieldRec.save(db)
                if let domain = fieldRec.asDomain() {
                    savedFields.append(domain)
                }
            }

            return TemplateOption(
                id: optionId,
                eventTypeId: eventTypeId,
                name: optionRec.name,
                description: optionRec.description,
                fields: savedFields
            )
        }
    }

    func deleteOption(id: Int64) async throws {
        _ = try await dbWriter.write { db in
            try OptionRecord.deleteOne(db, key: id)
        }
    }

    func fetchOptionValues(forEventId eventId: Int64) async throws -> [EventOptionValue] {
        try await dbWriter.read { db in
            try EventOptionValueRecord
                .filter(Column("eventId") == eventId)
                .fetchAll(db)
                .compactMap { $0.asDomain() }
        }
    }

    func saveOptionValues(forEventId eventId: Int64, values: [EventOptionValue]) async throws {
        try await dbWriter.write { db in
            try db.execute(
                sql: "DELETE FROM event_option_values WHERE eventId = ?",
                arguments: [eventId]
            )
            for value in values {
                var rec = EventOptionValueRecord(
                    id: nil,
                    eventId: eventId,
                    fieldId: value.fieldId,
                    textValue: value.textValue?.nilIfBlank,
                    photoPath: value.photoPath?.nilIfBlank,
                    clientId: value.clientId,
                    latitude: value.latitude,
                    longitude: value.longitude,
                    locationLabel: value.locationLabel?.nilIfBlank
                )
                try rec.save(db)
            }
        }
    }
}
