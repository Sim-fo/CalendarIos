import Foundation

struct CalendarEvent: Identifiable, Equatable, Sendable {
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

    var endAt: Date {
        startAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }
}

