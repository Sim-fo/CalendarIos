import Foundation

// MARK: - Todo

struct TodoItem: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: Int64
    var text: String
    var isDone: Bool
    let createdAt: Date
}

// MARK: - Tracker

struct TrackerItem: Identifiable, Equatable, Hashable, Codable, Sendable {
    static let defaultColorHex = 0xFF5DADE2

    let id: Int64
    var name: String
    var intervalDays: Int
    var createdDate: Date
    var lastResetDate: Date
    var colorHex: Int

    func daysSinceReset(referenceDate: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: lastResetDate)
        let end = calendar.startOfDay(for: referenceDate)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    func isOverdue(referenceDate: Date = Date(), calendar: Calendar = .current) -> Bool {
        daysSinceReset(referenceDate: referenceDate, calendar: calendar) >= max(intervalDays, 1)
    }

    /// Matches Android TrackerEntity.getMarkerDaysInMonth(year, month)
    func markerDays(inYear year: Int, month: Int, calendar: Calendar = .current) -> Set<Int> {
        let step = max(intervalDays, 1)
        var components = DateComponents(year: year, month: month, day: 1)
        components.calendar = calendar
        guard let monthStart = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }

        let resetStart = calendar.startOfDay(for: lastResetDate)
        let resetComponents = calendar.dateComponents([.year, .month, .day], from: resetStart)
        let isSameMonth = (resetComponents.year == year && resetComponents.month == month)
        var result = Set<Int>()

        for day in range {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }
            let diff = calendar.dateComponents([.day], from: resetStart, to: date).day ?? 0
            if diff > 0 && diff % step == 0 {
                if !(isSameMonth && resetComponents.day == day) {
                    result.insert(day)
                }
            }
        }
        return result
    }

    func hasMarker(on date: Date, calendar: Calendar = .current) -> Bool {
        let step = max(intervalDays, 1)
        let resetStart = calendar.startOfDay(for: lastResetDate)
        let targetStart = calendar.startOfDay(for: date)
        let diff = calendar.dateComponents([.day], from: resetStart, to: targetStart).day ?? 0
        return diff > 0 && diff % step == 0
    }
}

// MARK: - Birthday

struct BirthdayItem: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: Int64
    var name: String
    /// ISO format: "YYYY-MM-DD" or "--MM-DD" when birth year is omitted
    var birthDate: String
    var note: String?
    var contactPhone: String?
    var contactId: String?
    var photoPath: String?
    var remindWeekBefore: Bool
    var remindAtStart: Bool
    var lastAcknowledgedYear: Int?

    var hasBirthYear: Bool {
        !birthDate.hasPrefix("--")
    }

    func parsedComponents() -> (year: Int?, month: Int, day: Int)? {
        if birthDate.hasPrefix("--") {
            let parts = birthDate.dropFirst(2).split(separator: "-")
            guard parts.count == 2, let m = Int(parts[0]), let d = Int(parts[1]) else { return nil }
            return (nil, m, d)
        } else {
            let parts = birthDate.split(separator: "-")
            guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
            return (y, m, d)
        }
    }

    func dateInYear(_ year: Int, calendar: Calendar = .current) -> Date? {
        guard let parsed = parsedComponents() else { return nil }
        var day = parsed.day
        if parsed.month == 2 && day == 29 {
            var test = DateComponents(year: year, month: 2, day: 29)
            test.calendar = calendar
            if !test.isValidDate {
                day = 28
            }
        }
        return calendar.date(from: DateComponents(year: year, month: parsed.month, day: day))
    }

    func age(inYear year: Int) -> Int? {
        guard let birthYear = parsedComponents()?.year else { return nil }
        return max(0, year - birthYear)
    }

    func matches(date: Date, calendar: Calendar = .current) -> Bool {
        let year = calendar.component(.year, from: date)
        guard let target = dateInYear(year, calendar: calendar) else { return false }
        return calendar.isDate(target, inSameDayAs: date)
    }

    func isAcknowledged(inYear year: Int) -> Bool {
        lastAcknowledgedYear == year
    }

    static func formatISO(year: Int?, month: Int, day: Int) -> String {
        if let year {
            return String(format: "%04d-%02d-%02d", year, month, day)
        } else {
            return String(format: "--%02d-%02d", month, day)
        }
    }
}

// MARK: - Weekly Recurring Events

struct WeeklyRecurringSlot: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: Int64
    var weeklyEventId: Int64
    /// ISO weekday: 1 = Monday ... 7 = Sunday
    var dayOfWeek: Int
    /// "HH:mm"
    var startTime: String
    var durationMinutes: Int
    var note: String?
    var sortOrder: Int

    var hourAndMinute: (hour: Int, minute: Int) {
        let parts = startTime.split(separator: ":")
        let h = parts.first.flatMap { Int($0) } ?? 9
        let m = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        return (min(max(h, 0), 23), min(max(m, 0), 59))
    }
}

struct WeeklyRecurringItem: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: Int64
    var templateId: Int64?
    var customTitle: String?
    var customColorHex: Int?
    var reminderMinutes: Int
    var slots: [WeeklyRecurringSlot]
}

// MARK: - Client

struct ClientItem: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: Int64
    var name: String
    var phone: String?
    var email: String?
    var contactId: String?
    var photoPath: String?
    var note: String?
}

// MARK: - Map Marker (Location Link)

struct LocationLinkItem: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: Int64
    var url: String
    var title: String?
    var type: String?

    var displayTitle: String {
        if let title = title?.nilIfBlank {
            return title
        }
        return url
    }
}

// MARK: - Template Options & Option Fields

enum OptionFieldType: String, CaseIterable, Identifiable, Codable, Sendable {
    case variantText = "VARIANT_TEXT"
    case durationOverride = "DURATION_OVERRIDE"
    case photo = "PHOTO"
    case geoLocation = "GEO_LOCATION"
    case client = "CLIENT"

    var id: String { rawValue }

    var isVariantProperty: Bool {
        self == .durationOverride || self == .variantText
    }

    var isEventEditable: Bool {
        self == .photo || self == .geoLocation || self == .client
    }
}

struct TemplateOption: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: Int64
    let eventTypeId: Int64
    var name: String
    var description: String?
    var fields: [OptionField]
}

struct OptionField: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: Int64
    let optionId: Int64
    var fieldType: OptionFieldType
    var sortOrder: Int
    var label: String?
    var defaultDurationMinutes: Int?
    var defaultTextValue: String?
    var defaultLocationId: Int64?
    var photoPath: String?
}

struct EventOptionValue: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: Int64
    let eventId: Int64
    let fieldId: Int64
    var textValue: String?
    var photoPath: String?
    var clientId: Int64?
    var latitude: Double?
    var longitude: Double?
    var locationLabel: String?
}

// MARK: - Weekly Recurring Instance Generator

enum WeeklyEventInstanceGenerator {
    static func isoWeekday(for date: Date, calendar: Calendar) -> Int {
        // Foundation Calendar weekday: 1 = Sunday, 2 = Monday ... 7 = Saturday
        // ISO weekday: 1 = Monday ... 7 = Sunday
        let foundationWeekday = calendar.component(.weekday, from: date)
        return foundationWeekday == 1 ? 7 : (foundationWeekday - 1)
    }

    static func generateInstances(
        for weeklyEvent: WeeklyRecurringItem,
        template: EventType?,
        in interval: DateInterval,
        calendar: Calendar
    ) -> [CalendarEvent] {
        guard !weeklyEvent.slots.isEmpty else { return [] }
        let slotsByIsoDay = Dictionary(grouping: weeklyEvent.slots, by: \.dayOfWeek)
        let title = weeklyEvent.customTitle?.nilIfBlank ?? template?.title ?? "Untitled"
        let colorHex = weeklyEvent.customColorHex ?? template?.colorHex ?? CalendarColor.defaultEventHex

        var results: [CalendarEvent] = []
        var currentDay = calendar.startOfDay(for: interval.start)
        let endBoundary = interval.end

        while currentDay < endBoundary {
            let isoDay = isoWeekday(for: currentDay, calendar: calendar)
            if let daySlots = slotsByIsoDay[isoDay] {
                let dayStamp = calendar.component(.year, from: currentDay) * 10000
                    + calendar.component(.month, from: currentDay) * 100
                    + calendar.component(.day, from: currentDay)

                for slot in daySlots {
                    let hm = slot.hourAndMinute
                    let startAt = calendar.dateBySettingHour(hm.hour, minute: hm.minute, on: currentDay)
                    guard startAt >= interval.start && startAt < endBoundary else { continue }
                    // Deterministic negative ID per (weeklyEvent, slot, day)
                    let syntheticId = -((weeklyEvent.id * 1_000_000) + (slot.id * 1000) + Int64(dayStamp % 1000))
                    results.append(
                        CalendarEvent(
                            id: syntheticId,
                            eventTypeId: weeklyEvent.templateId,
                            customTitle: weeklyEvent.templateId == nil ? title : nil,
                            customColorHex: weeklyEvent.templateId == nil ? colorHex : nil,
                            title: title,
                            colorHex: colorHex,
                            startAt: startAt,
                            durationMinutes: max(1, slot.durationMinutes),
                            reminderMinutes: weeklyEvent.reminderMinutes,
                            note: slot.note,
                            recurringEventId: weeklyEvent.id
                        )
                    )
                }
            }

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) else { break }
            currentDay = nextDay
        }

        return results
    }
}
