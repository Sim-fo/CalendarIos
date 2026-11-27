import CoreGraphics
import Foundation

struct WeeklyTimelineEventLayout: Identifiable, Equatable {
    let id: Int64
    let event: CalendarEvent
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    static func make(
        events: [CalendarEvent],
        calendar: Calendar,
        columnWidth: CGFloat,
        hourHeight: CGFloat
    ) -> [WeeklyTimelineEventLayout] {
        let sorted = events.sorted { lhs, rhs in
            if lhs.startAt == rhs.startAt {
                if lhs.durationMinutes == rhs.durationMinutes {
                    return lhs.id < rhs.id
                }
                return lhs.durationMinutes < rhs.durationMinutes
            }
            return lhs.startAt < rhs.startAt
        }

        let clusters = makeClusters(from: sorted)
        let horizontalPadding: CGFloat = 6
        let columnSpacing: CGFloat = 4

        return clusters.flatMap { cluster in
            var columnEndDates: [Date] = []
            var placements: [(event: CalendarEvent, columnIndex: Int)] = []

            for event in cluster {
                if let reusableIndex = columnEndDates.firstIndex(where: { $0 <= event.startAt }) {
                    columnEndDates[reusableIndex] = event.endAt
                    placements.append((event, reusableIndex))
                } else {
                    columnEndDates.append(event.endAt)
                    placements.append((event, columnEndDates.count - 1))
                }
            }

            let columnCount = max(columnEndDates.count, 1)
            let totalSpacing = CGFloat(columnCount - 1) * columnSpacing
            let availableWidth = columnWidth - (horizontalPadding * 2) - totalSpacing
            let eventWidth = max(32, availableWidth / CGFloat(columnCount))

            return placements.map { placement in
                let components = calendar.dateComponents([.hour, .minute], from: placement.event.startAt)
                let startHour = CGFloat(components.hour ?? 0)
                let startMinute = CGFloat(components.minute ?? 0)
                let top = ((startHour * 60) + startMinute) / 60 * hourHeight
                let rawHeight = CGFloat(placement.event.durationMinutes) / 60 * hourHeight
                let height = max(38, rawHeight)
                let x = horizontalPadding + CGFloat(placement.columnIndex) * (eventWidth + columnSpacing)

                return WeeklyTimelineEventLayout(
                    id: placement.event.id,
                    event: placement.event,
                    x: x,
                    y: top,
                    width: eventWidth,
                    height: height
                )
            }
        }
    }

    private static func makeClusters(from events: [CalendarEvent]) -> [[CalendarEvent]] {
        var clusters: [[CalendarEvent]] = []
        var currentCluster: [CalendarEvent] = []
        var currentClusterMaxEnd: Date?

        for event in events {
            guard let maxEnd = currentClusterMaxEnd else {
                currentCluster = [event]
                currentClusterMaxEnd = event.endAt
                continue
            }

            if event.startAt < maxEnd {
                currentCluster.append(event)
                currentClusterMaxEnd = max(maxEnd, event.endAt)
            } else {
                clusters.append(currentCluster)
                currentCluster = [event]
                currentClusterMaxEnd = event.endAt
            }
        }

        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }

        return clusters
    }
}

struct WeeklySelectionGuide: Equatable {
    let date: Date
    let minuteOfDay: Int
    let durationMinutes: Int?

    init(date: Date, minuteOfDay: Int, durationMinutes: Int? = nil) {
        self.date = date
        self.minuteOfDay = minuteOfDay
        self.durationMinutes = durationMinutes
    }

    static func make(from date: Date, calendar: Calendar, slotMinutes: Int) -> WeeklySelectionGuide {
        let step = max(slotMinutes, 1)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let totalMinutes = ((hour * 60 + minute) / step) * step
        let normalizedHour = min(max(totalMinutes / 60, 0), 23)
        let normalizedMinute = min(max(totalMinutes % 60, 0), 59)
        let normalizedDate = calendar.date(
            bySettingHour: normalizedHour,
            minute: normalizedMinute,
            second: 0,
            of: date
        ) ?? date

        return WeeklySelectionGuide(
            date: normalizedDate,
            minuteOfDay: normalizedHour * 60 + normalizedMinute
        )
    }
}

extension CalendarEvent {
    func updating(startAt: Date) -> CalendarEvent {
        CalendarEvent(
            id: id,
            eventTypeId: eventTypeId,
            customTitle: customTitle,
            customColorHex: customColorHex,
            title: title,
            colorHex: colorHex,
            startAt: startAt,
            durationMinutes: durationMinutes,
            reminderMinutes: reminderMinutes,
            note: note,
            audioNotePath: audioNotePath,
            selectedOptionId: selectedOptionId,
            selectedOptionName: selectedOptionName,
            recurringEventId: recurringEventId
        )
    }

    func updating(durationMinutes: Int) -> CalendarEvent {
        CalendarEvent(
            id: id,
            eventTypeId: eventTypeId,
            customTitle: customTitle,
            customColorHex: customColorHex,
            title: title,
            colorHex: colorHex,
            startAt: startAt,
            durationMinutes: durationMinutes,
            reminderMinutes: reminderMinutes,
            note: note,
            audioNotePath: audioNotePath,
            selectedOptionId: selectedOptionId,
            selectedOptionName: selectedOptionName,
            recurringEventId: recurringEventId
        )
    }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
