import Foundation

struct CalendarEvent: Identifiable, Equatable, Hashable, Sendable {
    let id: Int64
    let eventTypeId: Int64?
    let customTitle: String?
    let customColorHex: Int?
    let title: String
    let colorHex: Int
    let startAt: Date
    let durationMinutes: Int
    let reminderMinutes: Int
    let note: String?
    let audioNotePath: String?
    let selectedOptionId: Int64?
    let selectedOptionName: String?
    let recurringEventId: Int64?

    init(
        id: Int64,
        eventTypeId: Int64?,
        customTitle: String?,
        customColorHex: Int?,
        title: String,
        colorHex: Int,
        startAt: Date,
        durationMinutes: Int,
        reminderMinutes: Int,
        note: String?,
        audioNotePath: String? = nil,
        selectedOptionId: Int64? = nil,
        selectedOptionName: String? = nil,
        recurringEventId: Int64? = nil
    ) {
        self.id = id
        self.eventTypeId = eventTypeId
        self.customTitle = customTitle
        self.customColorHex = customColorHex
        self.title = title
        self.colorHex = colorHex
        self.startAt = startAt
        self.durationMinutes = durationMinutes
        self.reminderMinutes = reminderMinutes
        self.note = note
        self.audioNotePath = audioNotePath
        self.selectedOptionId = selectedOptionId
        self.selectedOptionName = selectedOptionName
        self.recurringEventId = recurringEventId
    }

    var isRecurringInstance: Bool {
        recurringEventId != nil
    }

    var endAt: Date {
        startAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }
}
