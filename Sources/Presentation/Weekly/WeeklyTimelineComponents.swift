import SwiftUI

struct WeeklyDayHeader: View {
    let section: WeekDaySection
    let calendar: Calendar
    let width: CGFloat
    let todayHighlightColor: Color
    let onHeaderTap: () -> Void

    var body: some View {
        Button(action: onHeaderTap) {
            VStack(spacing: 2) {
                Text(shortWeekday)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(dayNumber)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 3) {
                    ForEach(Array(section.trackerColors.prefix(3).enumerated()), id: \.offset) { _, hex in
                        Circle()
                            .fill(Color(calendarHex: hex))
                            .frame(width: 5, height: 5)
                    }
                    if !section.birthdays.isEmpty {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("weekly.dayHeader")
        .frame(width: width, height: 52)
        .background(
            section.isToday
                ? todayHighlightColor
                : Color(uiColor: .secondarySystemBackground)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
    }

    private var shortWeekday: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: section.date).capitalized
    }

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter.string(from: section.date)
    }
}

struct TimeColumnView: View {
    let calendar: Calendar
    let use24hFormat: Bool
    let hourHeight: CGFloat
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Rectangle()
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                .frame(width: width)

            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(hourLabel(hour))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: width - 10, height: hourHeight, alignment: .topTrailing)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let components = DateComponents(calendar: calendar, hour: hour, minute: 0)
        let date = calendar.date(from: components) ?? Date()
        return CalendarDateFormatter.time(for: date, calendar: calendar, use24h: use24hFormat)
    }
}

struct TimeColumnHeaderPlaceholder: View {
    let width: CGFloat
    let height: CGFloat
    let showsTodayButton: Bool
    let onTodayTap: () -> Void

    var body: some View {
        Rectangle()
            .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            .frame(width: width, height: height)
            .overlay {
                if showsTodayButton {
                    Button(action: onTodayTap) {
                        Image(systemName: "scope")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.tint)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)
            }
    }
}

struct WeeklyTimelineDayColumn: View {
    let section: WeekDaySection
    let sectionIndex: Int
    let dayCount: Int
    let calendar: Calendar
    let use24hFormat: Bool
    let width: CGFloat
    let hourHeight: CGFloat
    let timelineHeight: CGFloat
    let selectionSlotMinutes: Int
    let longPressDuration: TimeInterval
    let isLongPressEnabled: Bool
    let gestureCoordinator: WeeklyGestureCoordinator
    let guideState: WeeklySelectionGuide?
    let guideHighlightColor: Color
    let todayHighlightColor: Color
    let scrollOffsetY: CGFloat
    let activeEventID: Int64?
    let selectedCopyEventID: Int64?
    let previewEvent: CalendarEvent?
    let onGuideStart: (CGPoint) -> Void
    let onGuideChange: (CGPoint) -> Void
    let onGuideCommit: (CGPoint) -> Void
    let onGuideCancel: () -> Void
    let onEventTap: (CalendarEvent) -> Void
    let onEventMoveStart: (CalendarEvent) -> Void
    let onEventMoveChange: (CalendarEvent, CGPoint) -> Void
    let onEventResizeStart: (CalendarEvent) -> Void
    let onEventResizeChange: (CalendarEvent, CGPoint) -> Void
    let onEventInteractionCommit: () -> Void
    let onEventInteractionCancel: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(section.isToday ? todayHighlightColor : Color.clear)
                .overlay {
                    if isLongPressEnabled {
                        LongPressCaptureView(
                            minimumDuration: longPressDuration,
                            gestureCoordinator: gestureCoordinator,
                            onBegan: { point in
                                onGuideStart(globalPoint(from: point))
                            },
                            onChanged: { point in
                                onGuideChange(globalPoint(from: point))
                            },
                            onEnded: { point in
                                onGuideCommit(globalPoint(from: point))
                            },
                            onCancelled: onGuideCancel
                        )
                    }
                }

            ForEach(hourMarkers, id: \.self) { hour in
                Rectangle()
                    .fill(hour == currentHour ? currentHourColor : Color.primary.opacity(0.06))
                    .frame(height: hour == currentHour ? 1.5 : 1)
                    .offset(y: CGFloat(hour) * hourHeight)
            }

            if let guideState, calendar.isDate(guideState.date, inSameDayAs: section.date) {
                Rectangle()
                    .fill(guideHighlightColor)

                Rectangle()
                    .fill(Color.accentColor.opacity(0.28))
                    .frame(height: CGFloat(selectionSlotMinutes) / 60 * hourHeight)
                    .offset(y: guideOffsetY(for: guideState))
            }

            if section.isToday {
                Rectangle()
                    .fill(currentTimeIndicatorColor)
                    .frame(height: 2)
                    .offset(y: currentTimeOffset)
            }

            ForEach(eventLayouts) { layout in
                WeeklyTimelineEventBlock(
                    event: layout.event,
                    calendar: calendar,
                    use24hFormat: use24hFormat,
                    width: layout.width,
                    height: layout.height,
                    isActive: activeEventID == layout.event.id,
                    isSelectedForCopy: selectedCopyEventID == layout.event.id,
                    longPressDuration: longPressDuration,
                    gestureCoordinator: gestureCoordinator,
                    onTap: {
                        onEventTap(layout.event)
                    },
                    onMoveStart: {
                        onEventMoveStart(layout.event)
                    },
                    onMoveChange: { translation in
                        onEventMoveChange(layout.event, translation)
                    },
                    onMoveCommit: onEventInteractionCommit,
                    onMoveCancel: onEventInteractionCancel,
                    onResizeStart: {
                        onEventResizeStart(layout.event)
                    },
                    onResizeChange: { translation in
                        onEventResizeChange(layout.event, translation)
                    },
                    onResizeCommit: onEventInteractionCommit,
                    onResizeCancel: onEventInteractionCancel
                )
                .offset(x: layout.x, y: layout.y)
                .opacity(activeEventID == layout.event.id ? 0.001 : 1)
            }

            if let previewLayout {
                WeeklyTimelineEventBlock(
                    event: previewLayout.event,
                    calendar: calendar,
                    use24hFormat: use24hFormat,
                    width: previewLayout.width,
                    height: previewLayout.height,
                    isActive: true,
                    isSelectedForCopy: false,
                    longPressDuration: longPressDuration,
                    gestureCoordinator: gestureCoordinator,
                    onTap: {},
                    onMoveStart: {},
                    onMoveChange: { _ in },
                    onMoveCommit: {},
                    onMoveCancel: {},
                    onResizeStart: {},
                    onResizeChange: { _ in },
                    onResizeCommit: {},
                    onResizeCancel: {}
                )
                .offset(x: previewLayout.x, y: previewLayout.y)
                .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: timelineHeight, alignment: .topLeading)
        .clipped()
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
    }

    private var hourMarkers: [Int] {
        Array(0...24)
    }

    private var currentHour: Int {
        calendar.component(.hour, from: Date())
    }

    private var currentHourColor: Color {
        section.isToday ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06)
    }

    private var currentTimeIndicatorColor: Color {
        Color.red.opacity(0.75)
    }

    private var currentTimeOffset: CGFloat {
        let components = calendar.dateComponents([.hour, .minute], from: Date())
        let hour = CGFloat(components.hour ?? 0)
        let minute = CGFloat(components.minute ?? 0)
        return ((hour * 60) + minute) / 60 * hourHeight
    }

    private var eventLayouts: [WeeklyTimelineEventLayout] {
        WeeklyTimelineEventLayout.make(
            events: section.events,
            calendar: calendar,
            columnWidth: width,
            hourHeight: hourHeight
        )
    }

    private var previewLayout: WeeklyTimelineEventLayout? {
        guard let previewEvent else { return nil }
        guard activeEventID == previewEvent.id else { return nil }
        guard calendar.isDate(previewEvent.startAt, inSameDayAs: section.date) else { return nil }

        let previewEvents = section.events.filter { $0.id != previewEvent.id } + [previewEvent]
        return WeeklyTimelineEventLayout.make(
            events: previewEvents,
            calendar: calendar,
            columnWidth: width,
            hourHeight: hourHeight
        )
        .first(where: { $0.id == previewEvent.id })
    }

    private func guideOffsetY(for guideState: WeeklySelectionGuide) -> CGFloat {
        CGFloat(guideState.minuteOfDay) / 60 * hourHeight
    }

    private func globalPoint(from localPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: CGFloat(sectionIndex) * width + localPoint.x,
            y: localPoint.y
        )
    }
}

struct WeeklyTimelineEventBlock: View {
    let event: CalendarEvent
    let calendar: Calendar
    let use24hFormat: Bool
    let width: CGFloat
    let height: CGFloat
    let isActive: Bool
    let isSelectedForCopy: Bool
    let longPressDuration: TimeInterval
    let gestureCoordinator: WeeklyGestureCoordinator
    let onTap: () -> Void
    let onMoveStart: () -> Void
    let onMoveChange: (CGPoint) -> Void
    let onMoveCommit: () -> Void
    let onMoveCancel: () -> Void
    let onResizeStart: () -> Void
    let onResizeChange: (CGPoint) -> Void
    let onResizeCommit: () -> Void
    let onResizeCancel: () -> Void

    static let resizeHandleHeight: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if event.isRecurringInstance {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(event.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
            }

            Text(timeRange)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let note = event.note, !note.isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(Color(calendarHex: event.colorHex).opacity(0.18))
        .overlay {
            EventTouchCaptureView(
                minimumDuration: longPressDuration,
                gestureCoordinator: gestureCoordinator,
                onTap: onTap,
                onMoveBegan: onMoveStart,
                onMoveChanged: onMoveChange,
                onMoveEnded: onMoveCommit,
                onMoveCancelled: onMoveCancel
            )
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(calendarHex: event.colorHex))
                .frame(width: 4)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 4) {
                Capsule()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: min(28, max(width - 16, 12)), height: 4)

                PanCaptureView(
                    gestureCoordinator: gestureCoordinator,
                    onBegan: onResizeStart,
                    onChanged: onResizeChange,
                    onEnded: onResizeCommit,
                    onCancelled: onResizeCancel
                )
                .frame(maxWidth: .infinity, minHeight: Self.resizeHandleHeight, maxHeight: Self.resizeHandleHeight)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isSelectedForCopy
                        ? CalendarColor.copyModeAccent
                        : (isActive ? Color.accentColor.opacity(0.7) : Color.clear),
                    lineWidth: isSelectedForCopy ? 2.5 : 2
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(
            color: isSelectedForCopy
                ? CalendarColor.copyModeAccent.opacity(0.35)
                : (isActive ? Color.accentColor.opacity(0.18) : .clear),
            radius: 8,
            y: 2
        )
    }

    private var timeRange: String {
        let start = CalendarDateFormatter.time(for: event.startAt, calendar: calendar, use24h: use24hFormat)
        let end = CalendarDateFormatter.time(for: event.endAt, calendar: calendar, use24h: use24hFormat)
        return "\(start) - \(end)"
    }
}

struct SelectionTimeHeaderView: View {
    let selectedDate: Date
    let durationMinutes: Int?
    let calendar: Calendar
    let use24hFormat: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(timeText)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()

            if let durationText {
                Text(durationText)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.tint)
            }

            Text(dateText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(CalendarColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var timeText: String {
        CalendarDateFormatter.time(for: selectedDate, calendar: calendar, use24h: use24hFormat)
    }

    private var durationText: String? {
        guard let durationMinutes, durationMinutes > 0 else { return nil }
        let hours = durationMinutes / 60
        let mins = durationMinutes % 60
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: selectedDate)
    }
}
