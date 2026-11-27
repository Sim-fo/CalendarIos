import Foundation

struct EventType: Identifiable, Equatable, Hashable, Sendable {
    let id: Int64
    let title: String
    let defaultDurationMinutes: Int
    let colorHex: Int
    let notifyBeforeMinutes: Int
}

struct EventTypeWithCount: Identifiable, Equatable, Hashable, Sendable {
    let eventType: EventType
    let eventCount: Int

    var id: Int64 { eventType.id }
}

struct EventTypeDraft: Equatable, Sendable {
    var id: Int64?
    var title: String
    var defaultDurationMinutes: Int
    var colorHex: Int
    var notifyBeforeMinutes: Int

    static func empty(defaultColorHex: Int = CalendarColor.pastelPresets[1]) -> EventTypeDraft {
        EventTypeDraft(
            id: nil,
            title: "",
            defaultDurationMinutes: 60,
            colorHex: defaultColorHex,
            notifyBeforeMinutes: 10
        )
    }

    init(
        id: Int64?,
        title: String,
        defaultDurationMinutes: Int,
        colorHex: Int,
        notifyBeforeMinutes: Int
    ) {
        self.id = id
        self.title = title
        self.defaultDurationMinutes = defaultDurationMinutes
        self.colorHex = colorHex
        self.notifyBeforeMinutes = notifyBeforeMinutes
    }

    init(eventType: EventType) {
        self.id = eventType.id
        self.title = eventType.title
        self.defaultDurationMinutes = eventType.defaultDurationMinutes
        self.colorHex = eventType.colorHex
        self.notifyBeforeMinutes = eventType.notifyBeforeMinutes
    }
}
