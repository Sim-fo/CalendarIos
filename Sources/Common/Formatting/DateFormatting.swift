import Foundation

extension Calendar {
    func startOfWeek(containing date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }

    func daysInWeek(containing date: Date) -> [Date] {
        let weekStart = startOfWeek(containing: date)
        return (0..<7).compactMap { dayOffset in
            self.date(byAdding: .day, value: dayOffset, to: weekStart)
        }
    }

    func dateBySettingHour(_ hour: Int, minute: Int, on date: Date) -> Date {
        let normalized = startOfDay(for: date)
        return self.date(bySettingHour: hour, minute: minute, second: 0, of: normalized) ?? normalized
    }
}

extension Date {
    var millisecondsSince1970: Int64 {
        Int64((timeIntervalSince1970 * 1000.0).rounded())
    }

    init(millisecondsSince1970: Int64) {
        self = Date(timeIntervalSince1970: TimeInterval(millisecondsSince1970) / 1000.0)
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum CalendarDateFormatter {
    static func weekdayHeader(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("EEE d")
        return formatter.string(from: date).capitalized
    }

    static func weekTitle(for weekStart: Date, calendar: Calendar) -> String {
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        let start = formatter.string(from: weekStart)
        let end = formatter.string(from: weekEnd)
        return "\(start) - \(end)"
    }

    static func time(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

