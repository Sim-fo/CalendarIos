import Foundation
import SwiftUI

@MainActor
final class AppSettingsStore: ObservableObject {
    static let maxCustomTabs = 3
    static let defaultCustomTabs: [AppFeatureTab] = [.todo, .trackers]
    static let allowedQuantizationSteps: [Int] = [5, 10, 15, 30, 60]

    private enum Keys {
        static let customTabs = "custom_tabs_v1"
        static let themeMode = "theme_mode"
        static let use24hFormat = "use_24h_format"
        static let firstDayOfWeek = "first_day_of_week"
        static let visibleDays = "number_of_visible_days"
        static let scrollStepDays = "scroll_step_days"
        static let showWeekFromCurrentDay = "show_week_from_current_day"
        static let allowHapticFeedback = "week_view_haptic_feedback"
        static let quantizationMinutes = "quantization_minutes"
        static let guideHighlightColorHex = "highlight_color_rgb"
        static let guideHighlightAlpha = "highlight_alpha"
        static let todayHighlightColorHex = "today_highlight_color_rgb"
        static let todayHighlightAlpha = "today_highlight_alpha"
        static let freeTimeThresholdMinutes = "free_time_threshold_minutes"
        static let lastEventTypeId = "last_event_type_id"
    }

    private let defaults: UserDefaults

    @Published var customTabs: [AppFeatureTab] {
        didSet {
            let sanitized = Self.sanitizeCustomTabs(customTabs)
            if sanitized != customTabs {
                customTabs = sanitized
                return
            }
            defaults.set(sanitized.map(\.rawValue), forKey: Keys.customTabs)
        }
    }

    @Published var themeMode: AppThemeMode {
        didSet { defaults.set(themeMode.rawValue, forKey: Keys.themeMode) }
    }

    @Published var use24hFormat: Bool {
        didSet { defaults.set(use24hFormat, forKey: Keys.use24hFormat) }
    }

    /// Matches Calendar.firstWeekday (1 = Sunday, 2 = Monday)
    @Published var firstDayOfWeek: Int {
        didSet {
            let clamped = (firstDayOfWeek == 1 || firstDayOfWeek == 2) ? firstDayOfWeek : 2
            if clamped != firstDayOfWeek {
                firstDayOfWeek = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.firstDayOfWeek)
        }
    }

    @Published var visibleDays: Int {
        didSet {
            let clamped = min(max(visibleDays, 1), 10)
            if clamped != visibleDays {
                visibleDays = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.visibleDays)
            if scrollStepDays > clamped {
                scrollStepDays = clamped
            }
        }
    }

    @Published var scrollStepDays: Int {
        didSet {
            let clamped = min(max(scrollStepDays, 1), visibleDays)
            if clamped != scrollStepDays {
                scrollStepDays = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.scrollStepDays)
        }
    }

    @Published var showWeekFromCurrentDay: Bool {
        didSet { defaults.set(showWeekFromCurrentDay, forKey: Keys.showWeekFromCurrentDay) }
    }

    @Published var allowHapticFeedback: Bool {
        didSet { defaults.set(allowHapticFeedback, forKey: Keys.allowHapticFeedback) }
    }

    @Published var quantizationMinutes: Int {
        didSet {
            let resolved = Self.allowedQuantizationSteps.contains(quantizationMinutes) ? quantizationMinutes : 30
            if resolved != quantizationMinutes {
                quantizationMinutes = resolved
                return
            }
            defaults.set(resolved, forKey: Keys.quantizationMinutes)
        }
    }

    @Published var guideHighlightColorHex: Int {
        didSet { defaults.set(guideHighlightColorHex, forKey: Keys.guideHighlightColorHex) }
    }

    @Published var guideHighlightAlphaPercent: Int {
        didSet {
            let clamped = min(max(guideHighlightAlphaPercent, 0), 25)
            if clamped != guideHighlightAlphaPercent {
                guideHighlightAlphaPercent = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.guideHighlightAlpha)
        }
    }

    @Published var todayHighlightColorHex: Int {
        didSet { defaults.set(todayHighlightColorHex, forKey: Keys.todayHighlightColorHex) }
    }

    @Published var todayHighlightAlphaPercent: Int {
        didSet {
            let clamped = min(max(todayHighlightAlphaPercent, 0), 25)
            if clamped != todayHighlightAlphaPercent {
                todayHighlightAlphaPercent = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.todayHighlightAlpha)
        }
    }

    @Published var freeTimeThresholdMinutes: Int {
        didSet {
            let clamped = max(freeTimeThresholdMinutes, 5)
            if clamped != freeTimeThresholdMinutes {
                freeTimeThresholdMinutes = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.freeTimeThresholdMinutes)
        }
    }

    @Published var lastSelectedEventTypeId: Int64? {
        didSet {
            if let lastSelectedEventTypeId {
                defaults.set(lastSelectedEventTypeId, forKey: Keys.lastEventTypeId)
            } else {
                defaults.removeObject(forKey: Keys.lastEventTypeId)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let storedTabs = defaults.stringArray(forKey: Keys.customTabs) {
            self.customTabs = Self.sanitizeCustomTabs(storedTabs.compactMap(AppFeatureTab.init(rawValue:)))
        } else {
            self.customTabs = Self.defaultCustomTabs
        }

        if let rawTheme = defaults.string(forKey: Keys.themeMode),
           let parsedTheme = AppThemeMode(rawValue: rawTheme) {
            self.themeMode = parsedTheme
        } else {
            self.themeMode = .system
        }

        self.use24hFormat = defaults.object(forKey: Keys.use24hFormat) as? Bool ?? true

        let storedFirstDay = defaults.object(forKey: Keys.firstDayOfWeek) as? Int ?? 2
        self.firstDayOfWeek = (storedFirstDay == 1 || storedFirstDay == 2) ? storedFirstDay : 2

        let storedVisibleDays = defaults.object(forKey: Keys.visibleDays) as? Int ?? 7
        let clampedVisibleDays = min(max(storedVisibleDays, 1), 10)
        self.visibleDays = clampedVisibleDays

        let storedScrollStep = defaults.object(forKey: Keys.scrollStepDays) as? Int ?? clampedVisibleDays
        self.scrollStepDays = min(max(storedScrollStep, 1), clampedVisibleDays)

        self.showWeekFromCurrentDay = defaults.object(forKey: Keys.showWeekFromCurrentDay) as? Bool ?? false
        self.allowHapticFeedback = defaults.object(forKey: Keys.allowHapticFeedback) as? Bool ?? true

        let storedQuantization = defaults.object(forKey: Keys.quantizationMinutes) as? Int ?? 30
        self.quantizationMinutes = Self.allowedQuantizationSteps.contains(storedQuantization) ? storedQuantization : 30

        self.guideHighlightColorHex = defaults.object(forKey: Keys.guideHighlightColorHex) as? Int ?? 0xFFB2EBF2
        self.guideHighlightAlphaPercent = min(max(defaults.object(forKey: Keys.guideHighlightAlpha) as? Int ?? 12, 0), 25)
        self.todayHighlightColorHex = defaults.object(forKey: Keys.todayHighlightColorHex) as? Int ?? 0xFF4DD0E1
        self.todayHighlightAlphaPercent = min(max(defaults.object(forKey: Keys.todayHighlightAlpha) as? Int ?? 9, 0), 25)
        self.freeTimeThresholdMinutes = max(defaults.object(forKey: Keys.freeTimeThresholdMinutes) as? Int ?? 30, 5)
        if let storedLastType = defaults.object(forKey: Keys.lastEventTypeId) as? NSNumber {
            let value = storedLastType.int64Value
            self.lastSelectedEventTypeId = value > 0 ? value : nil
        } else {
            self.lastSelectedEventTypeId = nil
        }
    }

    var effectiveCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = firstDayOfWeek
        return calendar
    }

    var guideHighlightColor: Color {
        Color(calendarHex: guideHighlightColorHex)
            .opacity(Double(guideHighlightAlphaPercent) / 100.0)
    }

    var todayHighlightColor: Color {
        Color(calendarHex: todayHighlightColorHex)
            .opacity(Double(todayHighlightAlphaPercent) / 100.0)
    }

    func isTabEnabled(_ tab: AppFeatureTab) -> Bool {
        customTabs.contains(tab)
    }

    @discardableResult
    func toggleTab(_ tab: AppFeatureTab) -> Bool {
        if let index = customTabs.firstIndex(of: tab) {
            customTabs.remove(at: index)
            return true
        }
        guard customTabs.count < Self.maxCustomTabs else {
            return false
        }
        customTabs.append(tab)
        return true
    }

    func moveCustomTabs(from source: IndexSet, to destination: Int) {
        customTabs.move(fromOffsets: source, toOffset: destination)
    }

    func resetCustomTabsToDefault() {
        customTabs = Self.defaultCustomTabs
    }

    private static func sanitizeCustomTabs(_ tabs: [AppFeatureTab]) -> [AppFeatureTab] {
        var seen = Set<AppFeatureTab>()
        var result: [AppFeatureTab] = []
        for tab in tabs where !seen.contains(tab) {
            seen.insert(tab)
            result.append(tab)
            if result.count == maxCustomTabs {
                break
            }
        }
        return result
    }
}
