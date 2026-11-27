import Foundation
import GRDB

struct TodoRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "todo_items"

    var id: Int64?
    var text: String
    var isDone: Bool
    var createdAtMillis: Int64
    var lastModifiedMillis: Int64

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    func asDomain() -> TodoItem? {
        guard let id else { return nil }
        return TodoItem(
            id: id,
            text: text,
            isDone: isDone,
            createdAt: Date(millisecondsSince1970: createdAtMillis)
        )
    }
}

struct TrackerRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "trackers"

    var id: Int64?
    var name: String
    var intervalDays: Int
    var createdDateMillis: Int64
    var lastResetDateMillis: Int64
    var colorHex: Int
    var lastModifiedMillis: Int64

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    func asDomain() -> TrackerItem? {
        guard let id else { return nil }
        return TrackerItem(
            id: id,
            name: name,
            intervalDays: intervalDays,
            createdDate: Date(millisecondsSince1970: createdDateMillis),
            lastResetDate: Date(millisecondsSince1970: lastResetDateMillis),
            colorHex: colorHex
        )
    }
}

struct BirthdayRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "birthdays"

    var id: Int64?
    var name: String
    var birthDate: String
    var note: String?
    var contactPhone: String?
    var contactId: String?
    var photoPath: String?
    var remindWeekBefore: Bool
    var remindAtStart: Bool
    var lastAcknowledgedYear: Int?
    var lastModifiedMillis: Int64

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    func asDomain() -> BirthdayItem? {
        guard let id else { return nil }
        return BirthdayItem(
            id: id,
            name: name,
            birthDate: birthDate,
            note: note,
            contactPhone: contactPhone,
            contactId: contactId,
            photoPath: photoPath,
            remindWeekBefore: remindWeekBefore,
            remindAtStart: remindAtStart,
            lastAcknowledgedYear: lastAcknowledgedYear
        )
    }
}

struct WeeklyRecurringEventRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "weekly_recurring_events"

    var id: Int64?
    var templateId: Int64?
    var customTitle: String?
    var customColorHex: Int?
    var reminderMinutes: Int
    var lastModifiedMillis: Int64

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct WeeklyRecurringEventSlotRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "weekly_recurring_event_slots"

    var id: Int64?
    var weeklyEventId: Int64
    var dayOfWeek: Int
    var startTime: String
    var durationMinutes: Int
    var note: String?
    var sortOrder: Int

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    func asDomain() -> WeeklyRecurringSlot? {
        guard let id else { return nil }
        return WeeklyRecurringSlot(
            id: id,
            weeklyEventId: weeklyEventId,
            dayOfWeek: dayOfWeek,
            startTime: startTime,
            durationMinutes: durationMinutes,
            note: note,
            sortOrder: sortOrder
        )
    }
}

struct ClientRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "clients"

    var id: Int64?
    var name: String
    var phone: String?
    var email: String?
    var contactId: String?
    var photoPath: String?
    var note: String?
    var lastModifiedMillis: Int64

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    func asDomain() -> ClientItem? {
        guard let id else { return nil }
        return ClientItem(
            id: id,
            name: name,
            phone: phone,
            email: email,
            contactId: contactId,
            photoPath: photoPath,
            note: note
        )
    }
}

struct LocationLinkRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "location_links"

    var id: Int64?
    var url: String
    var title: String?
    var type: String?
    var lastModifiedMillis: Int64

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    func asDomain() -> LocationLinkItem? {
        guard let id else { return nil }
        return LocationLinkItem(id: id, url: url, title: title, type: type)
    }
}

struct OptionRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "options"

    var id: Int64?
    var eventTypeId: Int64
    var name: String
    var description: String?
    var lastModifiedMillis: Int64

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct OptionFieldRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "option_fields"

    var id: Int64?
    var optionId: Int64
    var fieldType: String
    var sortOrder: Int
    var label: String?
    var defaultDurationMinutes: Int?
    var defaultTextValue: String?
    var defaultLocationId: Int64?
    var photoPath: String?
    var lastModifiedMillis: Int64

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    func asDomain() -> OptionField? {
        guard let id, let type = OptionFieldType(rawValue: fieldType) else { return nil }
        return OptionField(
            id: id,
            optionId: optionId,
            fieldType: type,
            sortOrder: sortOrder,
            label: label,
            defaultDurationMinutes: defaultDurationMinutes,
            defaultTextValue: defaultTextValue,
            defaultLocationId: defaultLocationId,
            photoPath: photoPath
        )
    }
}

struct EventOptionValueRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "event_option_values"

    var id: Int64?
    var eventId: Int64
    var fieldId: Int64
    var textValue: String?
    var photoPath: String?
    var clientId: Int64?
    var latitude: Double?
    var longitude: Double?
    var locationLabel: String?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    func asDomain() -> EventOptionValue? {
        guard let id else { return nil }
        return EventOptionValue(
            id: id,
            eventId: eventId,
            fieldId: fieldId,
            textValue: textValue,
            photoPath: photoPath,
            clientId: clientId,
            latitude: latitude,
            longitude: longitude,
            locationLabel: locationLabel
        )
    }
}
