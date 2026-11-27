import Foundation
import SwiftUI

enum AppThemeMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

enum AppFeatureTab: String, CaseIterable, Identifiable, Codable, Sendable {
    case todo
    case trackers
    case birthdays
    case templates
    case weeklyEvents
    case clients
    case mapMarkers

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .todo: return "feature.todo.title"
        case .trackers: return "feature.trackers.title"
        case .birthdays: return "feature.birthdays.title"
        case .templates: return "feature.templates.title"
        case .weeklyEvents: return "feature.weekly_events.title"
        case .clients: return "feature.clients.title"
        case .mapMarkers: return "feature.map_markers.title"
        }
    }

    var shortTabTitleKey: LocalizedStringKey {
        switch self {
        case .todo: return "tab.todo"
        case .trackers: return "tab.trackers"
        case .birthdays: return "tab.birthdays"
        case .templates: return "tab.templates"
        case .weeklyEvents: return "tab.weekly_events"
        case .clients: return "tab.clients"
        case .mapMarkers: return "tab.map_markers"
        }
    }

    var subtitleKey: LocalizedStringKey {
        switch self {
        case .todo: return "feature.todo.subtitle"
        case .trackers: return "feature.trackers.subtitle"
        case .birthdays: return "feature.birthdays.subtitle"
        case .templates: return "feature.templates.subtitle"
        case .weeklyEvents: return "feature.weekly_events.subtitle"
        case .clients: return "feature.clients.subtitle"
        case .mapMarkers: return "feature.map_markers.subtitle"
        }
    }

    var systemImage: String {
        switch self {
        case .todo: return "checklist"
        case .trackers: return "repeat"
        case .birthdays: return "gift"
        case .templates: return "square.stack.3d.up"
        case .weeklyEvents: return "calendar.badge.clock"
        case .clients: return "person.2"
        case .mapMarkers: return "mappin.and.ellipse"
        }
    }
}

enum RootTabSelection: Hashable {
    case calendar
    case feature(AppFeatureTab)
    case more
}

enum CalendarMode: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .day: return "calendar.mode.day"
        case .week: return "calendar.mode.week"
        case .month: return "calendar.mode.month"
        case .year: return "calendar.mode.year"
        }
    }

    var systemImage: String {
        switch self {
        case .day: return "calendar.day.timeline.leading"
        case .week: return "calendar"
        case .month: return "calendar.badge.clock"
        case .year: return "square.grid.3x3"
        }
    }
}
