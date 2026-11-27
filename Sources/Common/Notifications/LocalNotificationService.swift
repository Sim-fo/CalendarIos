import Foundation
@preconcurrency import UserNotifications

enum LocalNotificationService {
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains("-UITesting")
    }

    static func requestAuthorizationIfNeeded() {
        guard !isRunningTests else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    static func scheduleEventReminder(for event: CalendarEvent) {
        guard !isRunningTests, !event.isRecurringInstance, event.id > 0 else { return }
        let identifier = eventNotificationId(event.id)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard event.reminderMinutes >= 0 else { return }

        let fireDate = event.startAt.addingTimeInterval(-TimeInterval(max(0, event.reminderMinutes) * 60))
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = event.title
        if let note = event.note, !note.isEmpty {
            content.body = note
        } else {
            content.body = CalendarDateFormatter.time(for: event.startAt, calendar: .current, use24h: true)
        }
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    static func cancelEventReminder(eventId: Int64) {
        guard !isRunningTests else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [eventNotificationId(eventId)])
    }

    static func rescheduleBirthdayReminders(birthdays: [BirthdayItem]) {
        guard !isRunningTests else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { existing in
            let birthdayIds = existing.map(\.identifier).filter { $0.hasPrefix("birthday_") }
            center.removePendingNotificationRequests(withIdentifiers: birthdayIds)

            let calendar = Calendar.current
            for birthday in birthdays {
                guard let parsed = birthday.parsedComponents() else { continue }

                if birthday.remindAtStart {
                    var comps = DateComponents()
                    comps.month = parsed.month
                    comps.day = parsed.day
                    comps.hour = 9
                    comps.minute = 0

                    let content = UNMutableNotificationContent()
                    content.title = birthday.name
                    content.body = String(localized: "notifications.birthday_today")
                    content.sound = .default

                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                    let req = UNNotificationRequest(
                        identifier: "birthday_day_\(birthday.id)",
                        content: content,
                        trigger: trigger
                    )
                    center.add(req)
                }

                if birthday.remindWeekBefore {
                    let currentYear = calendar.component(.year, from: Date())
                    if let target = birthday.dateInYear(currentYear, calendar: calendar),
                       let weekBefore = calendar.date(byAdding: .day, value: -7, to: target) {
                        var comps = calendar.dateComponents([.month, .day], from: weekBefore)
                        comps.hour = 9
                        comps.minute = 0

                        let content = UNMutableNotificationContent()
                        content.title = birthday.name
                        content.body = String(localized: "notifications.birthday_week_before")
                        content.sound = .default

                        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                        let req = UNNotificationRequest(
                            identifier: "birthday_week_\(birthday.id)",
                            content: content,
                            trigger: trigger
                        )
                        center.add(req)
                    }
                }
            }
        }
    }

    private static func eventNotificationId(_ id: Int64) -> String {
        "event_\(id)"
    }
}
