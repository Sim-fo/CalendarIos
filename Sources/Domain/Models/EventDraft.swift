import Foundation

struct EventDraft: Equatable, Sendable {
    var id: Int64?
    var eventTypeId: Int64?
    var customTitle: String
    var customColorHex: Int?
    var startAt: Date
    var durationMinutes: Int
    var reminderMinutes: Int
    var note: String

    static func empty(on date: Date, calendar: Calendar = .current) -> EventDraft {
        EventDraft(
            id: nil,
            eventTypeId: nil,
            customTitle: "",
            customColorHex: CalendarColor.defaultEventHex,
            startAt: calendar.dateBySettingHour(9, minute: 0, on: date),
            durationMinutes: 60,
            reminderMinutes: 10,
            note: ""
        )
    }

    init(
        id: Int64?,
        eventTypeId: Int64?,
        customTitle: String,
        customColorHex: Int?,
        startAt: Date,
        durationMinutes: Int,
        reminderMinutes: Int,
        note: String
    ) {
        self.id = id
        self.eventTypeId = eventTypeId
        self.customTitle = customTitle
        self.customColorHex = customColorHex
        self.startAt = startAt
        self.durationMinutes = durationMinutes
        self.reminderMinutes = reminderMinutes
        self.note = note
    }

    init(event: CalendarEvent) {
        id = event.id
        eventTypeId = event.eventTypeId
        customTitle = event.customTitle ?? event.title
        customColorHex = event.customColorHex ?? event.colorHex
        startAt = event.startAt
        durationMinutes = event.durationMinutes
        reminderMinutes = event.reminderMinutes
        note = event.note ?? ""
    }
}

