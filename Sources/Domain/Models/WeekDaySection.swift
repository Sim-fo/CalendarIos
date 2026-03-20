import Foundation

struct WeekDaySection: Identifiable, Equatable {
    let id: Date
    let date: Date
    let isToday: Bool
    let events: [CalendarEvent]
}

