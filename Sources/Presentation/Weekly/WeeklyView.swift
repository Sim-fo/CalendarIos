import SwiftUI
import UIKit
import OSLog

struct WeeklyView: View {
    private let logger = Logger(subsystem: "com.simfogames.calendarios", category: "weekly-debug")
    @ObservedObject var viewModel: WeeklyViewModel
    private let calendar: Calendar
    @State private var guideState: WeeklySelectionGuide?
    @State private var guideInteraction: WeeklyGuideInteraction?
    @State private var activeEventInteraction: WeeklyEventInteraction?
    @State private var timelineScrollOffset: CGFloat = 0
    @State private var verticalViewportHeight: CGFloat = 0
    @State private var hasResolvedScrollView = false
    @State private var scrollViewDebugText = "unresolved"
    private let verticalScrollBridge = WeeklyScrollViewBridge()

    private let hourHeight: CGFloat = 72
    private let timeColumnWidth: CGFloat = 58
    private let dayColumnWidth: CGFloat = 178
    private let selectionSlotMinutes = 30
    private let manipulationSlotMinutes = 15
    private let minimumEventDurationMinutes = 15
    private let longPressDuration = 0.25
    private let autoScrollEdgeThreshold: CGFloat = 64
    private let autoScrollStep: CGFloat = 10

    init(viewModel: WeeklyViewModel, calendar: Calendar = .current) {
        self.viewModel = viewModel
        self.calendar = calendar
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CalendarColor.groupedBackground
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    header

                    if viewModel.isLoading && viewModel.sections.isEmpty {
                        ProgressView("Loading week...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        weeklyTimeline
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if let guideState {
                    VStack {
                        SelectionTimeHeaderView(
                            selectedDate: guideState.date,
                            calendar: calendar
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .allowsHitTesting(false)

                        Spacer()
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }

            }
            .navigationTitle("Weekly")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.openNewEvent(at: Date())
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $viewModel.isPresentingEditor) {
                EventEditorView(
                    draft: $viewModel.editorDraft,
                    eventTypes: viewModel.eventTypes,
                    isSaving: viewModel.isSaving,
                    onSave: viewModel.saveEditor,
                    onDelete: deleteAction,
                    onCancel: { viewModel.cancelEditor() }
                )
            }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button("OK") {
                    viewModel.dismissError()
                }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
            .task {
                viewModel.onAppear()
            }
            .task(id: autoScrollDirection) {
                guard let direction = autoScrollDirection else { return }
                logger.debug("Auto-scroll task started: \(String(describing: direction))")

                while !Task.isCancelled && autoScrollDirection == direction && guideInteraction != nil {
                    scrollTimeline(in: direction, step: autoScrollStep)
                    try? await Task.sleep(for: .milliseconds(16))
                }

                logger.debug("Auto-scroll task ended")
            }
            .onChange(of: autoScrollDirection) { _, newDirection in
                logger.debug("Edge direction changed: \(String(describing: newDirection))")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.weekTitle)
                .font(.title2.weight(.semibold))

            HStack(spacing: 10) {
                Button {
                    viewModel.showPreviousWeek()
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)

                Button("Today") {
                    viewModel.showCurrentWeek()
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewModel.showNextWeek()
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weeklyTimeline: some View {
        let timelineHeight = hourHeight * 24
        let displayedSections = resolvedSections

        return ZStack(alignment: .topLeading) {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(displayedSections) { section in
                            WeeklyDayHeader(
                                section: section,
                                calendar: calendar,
                                width: dayColumnWidth,
                                onAddTap: { viewModel.openNewEvent(on: section.date) }
                            )
                        }
                    }

                    ObservableScrollView(
                        bridge: verticalScrollBridge,
                        onScrollViewResolved: { scrollView in
                            hasResolvedScrollView = true
                            scrollViewDebugText = "bounds=\(Int(scrollView.bounds.height)) content=\(Int(scrollView.contentSize.height)) offset=\(Int(scrollView.contentOffset.y))"
                            logger.debug("Resolved scrollView: \(scrollViewDebugText)")
                        },
                        content: {
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(Array(displayedSections.enumerated()), id: \.element.id) { index, section in
                                    WeeklyTimelineDayColumn(
                                        section: section,
                                        sectionIndex: index,
                                        dayCount: displayedSections.count,
                                        calendar: calendar,
                                        width: dayColumnWidth,
                                        hourHeight: hourHeight,
                                        timelineHeight: timelineHeight,
                                        selectionSlotMinutes: selectionSlotMinutes,
                                        longPressDuration: longPressDuration,
                                        guideState: guideState,
                                        scrollOffsetY: timelineScrollOffset,
                                        activeEventID: activeEventInteraction?.eventID,
                                        onGuideStart: { point in
                                            guideInteraction = WeeklyGuideInteraction(point: point, fallbackIndex: index)
                                            withAnimation(.easeOut(duration: 0.12)) {
                                                guideState = makeGuideState(from: point, fallbackIndex: index)
                                            }
                                        },
                                        onGuideChange: { point in
                                            guideInteraction = WeeklyGuideInteraction(point: point, fallbackIndex: index)
                                            guideState = makeGuideState(from: point, fallbackIndex: index)
                                        },
                                        onGuideCommit: { point in
                                            guideInteraction = WeeklyGuideInteraction(point: point, fallbackIndex: index)
                                            let quantized = makeGuideState(from: point, fallbackIndex: index)
                                            guideInteraction = nil
                                            withAnimation(.easeOut(duration: 0.12)) {
                                                guideState = nil
                                            }
                                            viewModel.openNewEvent(at: quantized.date)
                                        },
                                        onGuideCancel: {
                                            guideInteraction = nil
                                            withAnimation(.easeOut(duration: 0.12)) {
                                                guideState = nil
                                            }
                                        },
                                        onEventTap: viewModel.openEditor(for:),
                                        onEventMoveStart: { event, point in
                                            beginEventMove(for: event, at: point, fallbackIndex: index)
                                        },
                                        onEventMoveChange: { event, point in
                                            updateEventMove(for: event, at: point, fallbackIndex: index)
                                        },
                                        onEventResizeStart: { event, point in
                                            beginEventResize(for: event, at: point, fallbackIndex: index)
                                        },
                                        onEventResizeChange: { event, point in
                                            updateEventResize(for: event, at: point, fallbackIndex: index)
                                        },
                                        onEventInteractionCommit: commitActiveEventInteraction,
                                        onEventInteractionCancel: cancelActiveEventInteraction
                                    )
                                }
                            }
                        },
                        onOffsetChange: { newOffset in
                            timelineScrollOffset = newOffset
                            if let scrollView = verticalScrollBridge.scrollView {
                                scrollViewDebugText = "bounds=\(Int(scrollView.bounds.height)) content=\(Int(scrollView.contentSize.height)) offset=\(Int(scrollView.contentOffset.y))"
                            }
                            refreshGuideStateIfNeeded()
                        },
                        onViewportHeightChange: { viewportHeight in
                            verticalViewportHeight = viewportHeight
                        }
                    )
                }
                .padding(.leading, timeColumnWidth)
            }

            VStack(spacing: 0) {
                TimeColumnHeaderPlaceholder(width: timeColumnWidth, height: 52)

                GeometryReader { proxy in
                    TimeColumnView(
                        calendar: calendar,
                        hourHeight: hourHeight,
                        width: timeColumnWidth
                    )
                    .frame(height: timelineHeight, alignment: .top)
                    .offset(y: -timelineScrollOffset)
                    .clipped()
                }
                .frame(width: timeColumnWidth)
            }
        }
        .background(CalendarColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.dismissError()
                }
            }
        )
    }

    private var resolvedSections: [WeekDaySection] {
        guard let interaction = activeEventInteraction else {
            return viewModel.sections
        }

        return viewModel.sections.map { section in
            var events = section.events.filter { $0.id != interaction.eventID }
            if calendar.isDate(interaction.previewEvent.startAt, inSameDayAs: section.date) {
                events.append(interaction.previewEvent)
                events.sort { lhs, rhs in
                    if lhs.startAt == rhs.startAt {
                        return lhs.durationMinutes < rhs.durationMinutes
                    }
                    return lhs.startAt < rhs.startAt
                }
            }

            return WeekDaySection(
                id: section.id,
                date: section.date,
                isToday: section.isToday,
                events: events
            )
        }
    }

    private var deleteAction: (() -> Void)? {
        guard viewModel.editorDraft.id != nil else {
            return nil
        }
        return { viewModel.deleteCurrentEvent() }
    }

    private func beginEventMove(for event: CalendarEvent, at point: CGPoint, fallbackIndex: Int) {
        let anchorMinutes = Int((point.y / hourHeight) * 60).clamped(to: 0...max(event.durationMinutes - 1, 0))
        activeEventInteraction = WeeklyEventInteraction(
            eventID: event.id,
            originalEvent: event,
            previewEvent: event,
            mode: .move(anchorMinutes: anchorMinutes),
            fallbackIndex: fallbackIndex
        )
    }

    private func updateEventMove(for event: CalendarEvent, at point: CGPoint, fallbackIndex: Int) {
        guard var interaction = activeEventInteraction, interaction.eventID == event.id else { return }
        let resolvedFallbackIndex = fallbackIndex

        let anchorMinutes: Int
        switch interaction.mode {
        case .move(let storedAnchorMinutes):
            anchorMinutes = storedAnchorMinutes
        case .resize:
            return
        }

        let targetDayIndex = resolvedDayIndex(from: point.x, fallbackIndex: resolvedFallbackIndex)
        let touchMinute = quantizedMinute(from: point.y, stepMinutes: manipulationSlotMinutes)
        let maxStartMinute = max((24 * 60) - event.durationMinutes, 0)
        let startMinute = (touchMinute - anchorMinutes).clamped(to: 0...maxStartMinute)
        let startAt = date(for: targetDayIndex, minuteOfDay: startMinute)

        interaction.previewEvent = event.updating(startAt: startAt)
        interaction.fallbackIndex = targetDayIndex
        activeEventInteraction = interaction
    }

    private func beginEventResize(for event: CalendarEvent, at point: CGPoint, fallbackIndex: Int) {
        let preview = event.updating(durationMinutes: max(minimumEventDurationMinutes, event.durationMinutes))
        activeEventInteraction = WeeklyEventInteraction(
            eventID: event.id,
            originalEvent: event,
            previewEvent: preview,
            mode: .resize,
            fallbackIndex: fallbackIndex
        )
        updateEventResize(for: event, at: point, fallbackIndex: fallbackIndex)
    }

    private func updateEventResize(for event: CalendarEvent, at point: CGPoint, fallbackIndex: Int) {
        guard var interaction = activeEventInteraction, interaction.eventID == event.id else { return }
        guard case .resize = interaction.mode else { return }

        let startMinute = minuteOfDay(for: interaction.previewEvent.startAt)
        let maxDuration = max((24 * 60) - startMinute, minimumEventDurationMinutes)
        let endMinute = quantizedMinute(from: point.y, stepMinutes: manipulationSlotMinutes)
        let duration = (endMinute - startMinute).clamped(to: minimumEventDurationMinutes...maxDuration)

        interaction.previewEvent = interaction.previewEvent.updating(durationMinutes: duration)
        interaction.fallbackIndex = fallbackIndex
        activeEventInteraction = interaction
    }

    private func commitActiveEventInteraction() {
        guard let interaction = activeEventInteraction else { return }
        activeEventInteraction = nil
        viewModel.applyInlineUpdate(from: interaction.originalEvent, to: interaction.previewEvent)
    }

    private func cancelActiveEventInteraction() {
        activeEventInteraction = nil
    }

    private func resolvedDayIndex(from x: CGFloat, fallbackIndex: Int) -> Int {
        let effectiveDayWidth = max(dayColumnWidth, 1)
        let rawDayIndex = Int(floor(x / effectiveDayWidth))
        let maxIndex = max(viewModel.sections.count - 1, 0)
        return rawDayIndex.clamped(to: 0...maxIndex)
    }

    private func quantizedMinute(from y: CGFloat, stepMinutes: Int) -> Int {
        let step = max(stepMinutes, 1)
        let visibleY = max(y, 0)
        let rawMinute = Int((visibleY / hourHeight) * 60)
        let quantizedMinute = (rawMinute / step) * step
        return quantizedMinute.clamped(to: 0...(24 * 60))
    }

    private func date(for dayIndex: Int, minuteOfDay: Int) -> Date {
        guard viewModel.sections.indices.contains(dayIndex) else {
            return viewModel.sections.first?.date ?? Date()
        }

        let sectionDate = viewModel.sections[dayIndex].date
        let hour = min(max(minuteOfDay / 60, 0), 23)
        let minute = min(max(minuteOfDay % 60, 0), 59)
        return calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: sectionDate
        ) ?? sectionDate
    }

    private func minuteOfDay(for date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private var autoScrollDirection: WeeklyAutoScrollDirection? {
        guard let interaction = guideInteraction, verticalViewportHeight > 0 else {
            return nil
        }

        let viewportY = interaction.point.y - timelineScrollOffset

        if viewportY < autoScrollEdgeThreshold {
            return .up
        }

        if viewportY > verticalViewportHeight - autoScrollEdgeThreshold {
            return .down
        }

        return nil
    }

    private func makeGuideState(from point: CGPoint, fallbackIndex: Int) -> WeeklySelectionGuide {
        let effectiveDayWidth = max(dayColumnWidth, 1)
        let rawDayIndex = Int(floor(point.x / effectiveDayWidth))
        let clampedDayIndex = min(max(rawDayIndex, 0), max(viewModel.sections.count - 1, 0))
        let resolvedIndex = viewModel.sections.indices.contains(clampedDayIndex) ? clampedDayIndex : fallbackIndex
        let resolvedSection = viewModel.sections[resolvedIndex]

        let visibleY = max(point.y, 0)
        let maxMinutes = 24 * 60 - selectionSlotMinutes
        let rawMinutes = Int((visibleY / hourHeight) * 60)
        let quantizedMinutes = ((rawMinutes / selectionSlotMinutes) * selectionSlotMinutes).clamped(to: 0...maxMinutes)
        let hour = quantizedMinutes / 60
        let minute = quantizedMinutes % 60

        let selectedDate = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: resolvedSection.date
        ) ?? resolvedSection.date

        return WeeklySelectionGuide(
            date: selectedDate,
            minuteOfDay: quantizedMinutes
        )
    }

    private func refreshGuideStateIfNeeded() {
        guard let interaction = guideInteraction else { return }
        guideState = makeGuideState(from: interaction.point, fallbackIndex: interaction.fallbackIndex)
    }

    private func scrollTimeline(in direction: WeeklyAutoScrollDirection, step: CGFloat) {
        guard let scrollView = verticalScrollBridge.scrollView else {
            logger.debug("scrollTimeline skipped: no resolved UIScrollView")
            return
        }

        let currentOffset = scrollView.contentOffset.y
        let maxOffset = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
        let delta = direction == .up ? -step : step
        let targetOffset = max(0, min(currentOffset + delta, maxOffset))
        let appliedDelta = targetOffset - currentOffset

        guard abs(targetOffset - currentOffset) > .ulpOfOne else {
            logger.debug("scrollTimeline no-op: dir=\(String(describing: direction)) current=\(Int(currentOffset)) max=\(Int(maxOffset))")
            return
        }

        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: targetOffset), animated: false)
        timelineScrollOffset = targetOffset
        scrollViewDebugText = "bounds=\(Int(scrollView.bounds.height)) content=\(Int(scrollView.contentSize.height)) offset=\(Int(scrollView.contentOffset.y))"
        logger.debug("scrollTimeline applied: dir=\(String(describing: direction)) from=\(Int(currentOffset)) to=\(Int(targetOffset)) max=\(Int(maxOffset))")
        if let interaction = guideInteraction {
            guideInteraction = WeeklyGuideInteraction(
                point: CGPoint(x: interaction.point.x, y: interaction.point.y + appliedDelta),
                fallbackIndex: interaction.fallbackIndex
            )
        }
        refreshGuideStateIfNeeded()
    }
}

private struct WeeklyDayHeader: View {
    let section: WeekDaySection
    let calendar: Calendar
    let width: CGFloat
    let onAddTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(CalendarDateFormatter.weekdayHeader(for: section.date, calendar: calendar))
                    .font(.headline)

                Text(section.isToday ? "Today" : "\(section.events.count) events")
                    .font(.caption.weight(section.isToday ? .semibold : .regular))
                    .foregroundStyle(section.isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }

            Spacer(minLength: 0)

            Button(action: onAddTap) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(width: width, height: 52, alignment: .topLeading)
        .background(section.isToday ? Color.accentColor.opacity(0.08) : Color.clear)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
    }
}

private struct TimeColumnView: View {
    let calendar: Calendar
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
        return CalendarDateFormatter.time(for: date, calendar: calendar)
    }
}

private struct TimeColumnHeaderPlaceholder: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            .frame(width: width, height: height)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)
            }
    }
}

private struct WeeklyTimelineDayColumn: View {
    let section: WeekDaySection
    let sectionIndex: Int
    let dayCount: Int
    let calendar: Calendar
    let width: CGFloat
    let hourHeight: CGFloat
    let timelineHeight: CGFloat
    let selectionSlotMinutes: Int
    let longPressDuration: TimeInterval
    let guideState: WeeklySelectionGuide?
    let scrollOffsetY: CGFloat
    let activeEventID: Int64?
    let onGuideStart: (CGPoint) -> Void
    let onGuideChange: (CGPoint) -> Void
    let onGuideCommit: (CGPoint) -> Void
    let onGuideCancel: () -> Void
    let onEventTap: (CalendarEvent) -> Void
    let onEventMoveStart: (CalendarEvent, CGPoint) -> Void
    let onEventMoveChange: (CalendarEvent, CGPoint) -> Void
    let onEventResizeStart: (CalendarEvent, CGPoint) -> Void
    let onEventResizeChange: (CalendarEvent, CGPoint) -> Void
    let onEventInteractionCommit: () -> Void
    let onEventInteractionCancel: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(section.isToday ? Color.accentColor.opacity(0.06) : Color.clear)
                .overlay {
                    LongPressCaptureView(
                        minimumDuration: longPressDuration,
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

            ForEach(hourMarkers, id: \.self) { hour in
                Rectangle()
                    .fill(hour == currentHour ? currentHourColor : Color.primary.opacity(0.06))
                    .frame(height: hour == currentHour ? 1.5 : 1)
                    .offset(y: CGFloat(hour) * hourHeight)
            }

            if let guideState, calendar.isDate(guideState.date, inSameDayAs: section.date) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.12))

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
                    width: layout.width,
                    height: layout.height,
                    isActive: activeEventID == layout.event.id,
                    longPressDuration: longPressDuration,
                    onTap: {
                        onEventTap(layout.event)
                    },
                    onMoveStart: { point in
                        onEventMoveStart(layout.event, eventGlobalPoint(from: point, layout: layout))
                    },
                    onMoveChange: { point in
                        onEventMoveChange(layout.event, eventGlobalPoint(from: point, layout: layout))
                    },
                    onMoveCommit: onEventInteractionCommit,
                    onMoveCancel: onEventInteractionCancel,
                    onResizeStart: { point in
                        onEventResizeStart(layout.event, eventGlobalPoint(from: point, layout: layout, localYInset: layout.height - WeeklyTimelineEventBlock.resizeHandleHeight))
                    },
                    onResizeChange: { point in
                        onEventResizeChange(layout.event, eventGlobalPoint(from: point, layout: layout, localYInset: layout.height - WeeklyTimelineEventBlock.resizeHandleHeight))
                    },
                    onResizeCommit: onEventInteractionCommit,
                    onResizeCancel: onEventInteractionCancel
                )
                .offset(x: layout.x, y: layout.y)
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

    private func date(at yOffset: CGFloat) -> Date {
        let clampedY = min(max(yOffset, 0), timelineHeight)
        let totalMinutes = Int((clampedY / hourHeight) * 60)
        let hour = min(max(totalMinutes / 60, 0), 23)
        let minute = min(max(totalMinutes % 60, 0), 59)
        return calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: section.date
        ) ?? section.date
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

    private func eventGlobalPoint(from localPoint: CGPoint, layout: WeeklyTimelineEventLayout, localYInset: CGFloat = 0) -> CGPoint {
        CGPoint(
            x: CGFloat(sectionIndex) * width + layout.x + localPoint.x,
            y: layout.y + localYInset + localPoint.y
        )
    }
}

private struct WeeklyTimelineEventBlock: View {
    let event: CalendarEvent
    let calendar: Calendar
    let width: CGFloat
    let height: CGFloat
    let isActive: Bool
    let longPressDuration: TimeInterval
    let onTap: () -> Void
    let onMoveStart: (CGPoint) -> Void
    let onMoveChange: (CGPoint) -> Void
    let onMoveCommit: () -> Void
    let onMoveCancel: () -> Void
    let onResizeStart: (CGPoint) -> Void
    let onResizeChange: (CGPoint) -> Void
    let onResizeCommit: () -> Void
    let onResizeCancel: () -> Void

    static let resizeHandleHeight: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(event.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)

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
                onTap: onTap,
                onMoveBegan: onMoveStart,
                onMoveChanged: onMoveChange,
                onMoveEnded: { _ in onMoveCommit() },
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
                    onBegan: onResizeStart,
                    onChanged: onResizeChange,
                    onEnded: { _ in onResizeCommit() },
                    onCancelled: onResizeCancel
                )
                .frame(maxWidth: .infinity, minHeight: Self.resizeHandleHeight, maxHeight: Self.resizeHandleHeight)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isActive ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: isActive ? Color.accentColor.opacity(0.18) : .clear, radius: 8, y: 2)
    }

    private var timeRange: String {
        let start = CalendarDateFormatter.time(for: event.startAt, calendar: calendar)
        let end = CalendarDateFormatter.time(for: event.endAt, calendar: calendar)
        return "\(start) - \(end)"
    }
}

private struct WeeklyTimelineEventLayout: Identifiable {
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

private struct WeeklySelectionGuide: Equatable {
    let date: Date
    let minuteOfDay: Int

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

private struct SelectionTimeHeaderView: View {
    let selectedDate: Date
    let calendar: Calendar

    var body: some View {
        VStack(spacing: 2) {
            Text(timeText)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()

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
        CalendarDateFormatter.time(for: selectedDate, calendar: calendar)
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

private struct LongPressCaptureView: UIViewRepresentable {
    let minimumDuration: TimeInterval
    let onBegan: (CGPoint) -> Void
    let onChanged: (CGPoint) -> Void
    let onEnded: (CGPoint) -> Void
    let onCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onBegan: onBegan,
            onChanged: onChanged,
            onEnded: onEnded,
            onCancelled: onCancelled
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let recognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        recognizer.minimumPressDuration = minimumDuration
        recognizer.allowableMovement = 18
        recognizer.cancelsTouchesInView = true
        view.addGestureRecognizer(recognizer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let recognizer = uiView.gestureRecognizers?.first as? UILongPressGestureRecognizer else {
            return
        }
        recognizer.minimumPressDuration = minimumDuration
    }

    final class Coordinator: NSObject {
        private let onBegan: (CGPoint) -> Void
        private let onChanged: (CGPoint) -> Void
        private let onEnded: (CGPoint) -> Void
        private let onCancelled: () -> Void

        init(
            onBegan: @escaping (CGPoint) -> Void,
            onChanged: @escaping (CGPoint) -> Void,
            onEnded: @escaping (CGPoint) -> Void,
            onCancelled: @escaping () -> Void
        ) {
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onCancelled = onCancelled
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            let point = recognizer.location(in: recognizer.view)

            switch recognizer.state {
            case .began:
                onBegan(point)
            case .changed:
                onChanged(point)
            case .ended:
                onEnded(point)
            case .cancelled, .failed:
                onCancelled()
            default:
                break
            }
        }
    }
}

private struct EventTouchCaptureView: UIViewRepresentable {
    let minimumDuration: TimeInterval
    let onTap: () -> Void
    let onMoveBegan: (CGPoint) -> Void
    let onMoveChanged: (CGPoint) -> Void
    let onMoveEnded: (CGPoint) -> Void
    let onMoveCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTap: onTap,
            onMoveBegan: onMoveBegan,
            onMoveChanged: onMoveChanged,
            onMoveEnded: onMoveEnded,
            onMoveCancelled: onMoveCancelled
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let tapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )

        let longPressRecognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPressRecognizer.minimumPressDuration = minimumDuration
        longPressRecognizer.allowableMovement = 18
        longPressRecognizer.cancelsTouchesInView = true

        tapRecognizer.require(toFail: longPressRecognizer)

        view.addGestureRecognizer(tapRecognizer)
        view.addGestureRecognizer(longPressRecognizer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let longPressRecognizer = uiView.gestureRecognizers?.compactMap({ $0 as? UILongPressGestureRecognizer }).first else {
            return
        }
        longPressRecognizer.minimumPressDuration = minimumDuration
    }

    final class Coordinator: NSObject {
        private let onTap: () -> Void
        private let onMoveBegan: (CGPoint) -> Void
        private let onMoveChanged: (CGPoint) -> Void
        private let onMoveEnded: (CGPoint) -> Void
        private let onMoveCancelled: () -> Void

        init(
            onTap: @escaping () -> Void,
            onMoveBegan: @escaping (CGPoint) -> Void,
            onMoveChanged: @escaping (CGPoint) -> Void,
            onMoveEnded: @escaping (CGPoint) -> Void,
            onMoveCancelled: @escaping () -> Void
        ) {
            self.onTap = onTap
            self.onMoveBegan = onMoveBegan
            self.onMoveChanged = onMoveChanged
            self.onMoveEnded = onMoveEnded
            self.onMoveCancelled = onMoveCancelled
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onTap()
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            let point = recognizer.location(in: recognizer.view)

            switch recognizer.state {
            case .began:
                onMoveBegan(point)
            case .changed:
                onMoveChanged(point)
            case .ended:
                onMoveEnded(point)
            case .cancelled, .failed:
                onMoveCancelled()
            default:
                break
            }
        }
    }
}

private struct PanCaptureView: UIViewRepresentable {
    let onBegan: (CGPoint) -> Void
    let onChanged: (CGPoint) -> Void
    let onEnded: (CGPoint) -> Void
    let onCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onBegan: onBegan,
            onChanged: onChanged,
            onEnded: onEnded,
            onCancelled: onCancelled
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let recognizer = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        recognizer.cancelsTouchesInView = true
        view.addGestureRecognizer(recognizer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator: NSObject {
        private let onBegan: (CGPoint) -> Void
        private let onChanged: (CGPoint) -> Void
        private let onEnded: (CGPoint) -> Void
        private let onCancelled: () -> Void

        init(
            onBegan: @escaping (CGPoint) -> Void,
            onChanged: @escaping (CGPoint) -> Void,
            onEnded: @escaping (CGPoint) -> Void,
            onCancelled: @escaping () -> Void
        ) {
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onCancelled = onCancelled
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let point = recognizer.location(in: recognizer.view)

            switch recognizer.state {
            case .began:
                onBegan(point)
            case .changed:
                onChanged(point)
            case .ended:
                onEnded(point)
            case .cancelled, .failed:
                onCancelled()
            default:
                break
            }
        }
    }
}

private struct ObservableScrollView<Content: View>: View {
    let bridge: WeeklyScrollViewBridge
    let onScrollViewResolved: (UIScrollView) -> Void
    let content: () -> Content
    let onOffsetChange: (CGFloat) -> Void
    let onViewportHeightChange: (CGFloat) -> Void

    init(
        bridge: WeeklyScrollViewBridge,
        onScrollViewResolved: @escaping (UIScrollView) -> Void,
        @ViewBuilder content: @escaping () -> Content,
        onOffsetChange: @escaping (CGFloat) -> Void,
        onViewportHeightChange: @escaping (CGFloat) -> Void
    ) {
        self.bridge = bridge
        self.onScrollViewResolved = onScrollViewResolved
        self.content = content
        self.onOffsetChange = onOffsetChange
        self.onViewportHeightChange = onViewportHeightChange
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            content()
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: VerticalScrollOffsetPreferenceKey.self, value: proxy.frame(in: .named("weeklyTimelineScroll")).minY)
                    }
                )
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        onViewportHeightChange(proxy.size.height)
                    }
                    .onChange(of: proxy.size.height) { _, newHeight in
                        onViewportHeightChange(newHeight)
                    }
            }
        )
        .coordinateSpace(name: "weeklyTimelineScroll")
        .onPreferenceChange(VerticalScrollOffsetPreferenceKey.self) { minY in
            onOffsetChange(-minY)
        }
        .background(
            ScrollViewResolverView { scrollView in
                bridge.scrollView = scrollView
                onScrollViewResolved(scrollView)
            }
        )
    }
}

private struct VerticalScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private enum WeeklyAutoScrollDirection: Hashable {
    case up
    case down
}

private struct WeeklyGuideInteraction {
    let point: CGPoint
    let fallbackIndex: Int
}

private struct WeeklyEventInteraction {
    let eventID: Int64
    let originalEvent: CalendarEvent
    var previewEvent: CalendarEvent
    let mode: WeeklyEventInteractionMode
    var fallbackIndex: Int
}

private enum WeeklyEventInteractionMode {
    case move(anchorMinutes: Int)
    case resize
}

private final class WeeklyScrollViewBridge {
    weak var scrollView: UIScrollView?
}

private struct ScrollViewResolverView: UIViewRepresentable {
    let onResolve: (UIScrollView) -> Void

    func makeUIView(context: Context) -> UIView {
        ResolverUIView(onResolve: onResolve)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let resolverView = uiView as? ResolverUIView {
            resolverView.onResolve = onResolve
            resolverView.resolveIfNeeded()
        }
    }
}

private final class ResolverUIView: UIView {
    var onResolve: (UIScrollView) -> Void

    init(onResolve: @escaping (UIScrollView) -> Void) {
        self.onResolve = onResolve
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        resolveIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        resolveIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        resolveIfNeeded()
    }

    func resolveIfNeeded() {
        guard let scrollView = resolvedWeeklyVerticalScrollView() else { return }
        onResolve(scrollView)
    }
}

private extension UIView {
    func resolvedWeeklyVerticalScrollView() -> UIScrollView? {
        var root: UIView = self
        while let parent = root.superview {
            root = parent
        }

        let allScrollViews = root.allDescendantScrollViews()

        let verticalCandidates = allScrollViews.filter { scrollView in
            scrollView.layoutIfNeeded()
            let contentHeight = scrollView.contentSize.height
            let boundsHeight = scrollView.bounds.height
            return contentHeight > boundsHeight + 1 || scrollView.alwaysBounceVertical
        }

        if let bestVertical = verticalCandidates.max(by: { lhs, rhs in
            (lhs.contentSize.height - lhs.bounds.height) < (rhs.contentSize.height - rhs.bounds.height)
        }) {
            return bestVertical
        }

        return allScrollViews.last
    }

    func allDescendantScrollViews() -> [UIScrollView] {
        var result: [UIScrollView] = []

        func collect(from view: UIView) {
            if let scrollView = view as? UIScrollView {
                result.append(scrollView)
            }
            for subview in view.subviews {
                collect(from: subview)
            }
        }

        collect(from: self)
        return result
    }
}

#Preview {
    let dependencies = try? CalendarDependencies.preview()
    if let dependencies {
        RootContentView(dependencies: dependencies)
    } else {
        Text("Preview unavailable")
    }
}

private extension CalendarEvent {
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
            note: note
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
            note: note
        )
    }
}
