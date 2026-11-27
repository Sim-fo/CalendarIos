import Foundation

struct WeekDaySection: Identifiable, Equatable {
    let id: Date
    let date: Date
    let isToday: Bool
    let events: [CalendarEvent]
    let trackerColors: [Int]
    let birthdays: [BirthdayItem]

    init(
        id: Date,
        date: Date,
        isToday: Bool,
        events: [CalendarEvent],
        trackerColors: [Int] = [],
        birthdays: [BirthdayItem] = []
    ) {
        self.id = id
        self.date = date
        self.isToday = isToday
        self.events = events
        self.trackerColors = trackerColors
        self.birthdays = birthdays
    }
}
