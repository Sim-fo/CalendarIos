import SwiftUI
import UIKit

struct WeeklyView: View {
    @ObservedObject var viewModel: WeeklyViewModel
    @AppStorage("number_of_visible_days") private var rangeStepDaysPreference = 7
    private let showsNavigationChrome: Bool
    private let onWeekTitleTap: ((Date) -> Void)?
    private let onDayHeaderTap: ((Date) -> Void)?
    private let calendar: Calendar
    @State private var guideState: WeeklySelectionGuide?
    @State private var guideInteraction: WeeklyGuideInteraction?
    @State private var activeEventInteraction: WeeklyEventInteraction?
    @State private var timelineScrollOffset: CGFloat = 0
    @State private var verticalViewportHeight: CGFloat = 0
    @State private var horizontalScrollOffset: CGFloat = 0
    @State private var horizontalViewportWidth: CGFloat = 0
    @State private var hourHeight: CGFloat = 72
    @State private var dayColumnWidth: CGFloat = 88
    @State private var pinchInteraction: WeeklyPinchInteraction?
    @State private var didRestoreInitialHorizontalPosition = false
    private let verticalScrollBridge = ScrollViewBridge()
    private let horizontalScrollBridge = ScrollViewBridge()

    private let timeColumnWidth: CGFloat = 58
    private let dayHeaderHeight: CGFloat = 52
    private let selectionSlotMinutes = 30
    private let manipulationSlotMinutes = 15
    private let minimumEventDurationMinutes = 15
    private let longPressDuration = 0.25
    private let autoScrollEdgeThreshold: CGFloat = 64
    private let autoScrollStep: CGFloat = 10
    private let maximumHourHeight: CGFloat = 132
    private let minimumDayColumnWidth: CGFloat = 72
    private let maximumDayColumnWidth: CGFloat = 320
    private let horizontalPinchSensitivity: CGFloat = 0.8
    private let verticalPinchSensitivity: CGFloat = 0.9

    init(
        viewModel: WeeklyViewModel,
        calendar: Calendar = .current,
        showsNavigationChrome: Bool = true,
        onWeekTitleTap: ((Date) -> Void)? = nil,
        onDayHeaderTap: ((Date) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.calendar = calendar
        self.showsNavigationChrome = showsNavigationChrome
        self.onWeekTitleTap = onWeekTitleTap
        self.onDayHeaderTap = onDayHeaderTap
    }

    var body: some View {
        Group {
            if showsNavigationChrome {
                NavigationStack {
                    weeklyContent
                }
            } else {
                weeklyContent
            }
        }
    }

    @ViewBuilder
    private var weeklyContent: some View {
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
        .if(showsNavigationChrome) { view in
            view
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

            while !Task.isCancelled && autoScrollDirection == direction && guideInteraction != nil {
                scrollTimeline(in: direction, step: autoScrollStep)
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
        .onChange(of: viewModel.sections.first?.date) { oldDate, newDate in
            guard let newDate else { return }

            if !didRestoreInitialHorizontalPosition {
                restoreInitialHorizontalPositionIfNeeded()
                return
            }

            if let oldDate, newDate < oldDate, let scrollView = horizontalScrollBridge.scrollView {
                let prependedDays = dayDistance(from: newDate, to: oldDate)
                guard prependedDays > 0 else { return }
                let adjustedOffset = scrollView.contentOffset.x + CGFloat(prependedDays) * dayColumnWidth
                scrollView.setContentOffset(
                    CGPoint(x: adjustedOffset, y: scrollView.contentOffset.y),
                    animated: false
                )
                horizontalScrollOffset = adjustedOffset
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                HStack {
                    monthHeaderButton(
                        text: primaryMonthLabel,
                        date: visibleFirstDate,
                        alignment: .leading
                    )

                    Spacer(minLength: 0)

                    if let secondaryMonthLabel {
                        monthHeaderButton(
                            text: secondaryMonthLabel,
                            date: visibleLastDate,
                            alignment: .trailing
                        )
                    }
                }

                HStack(spacing: 2) {
                    Button {
                        scrollHorizontally(by: -rangeStepDays)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        scrollHorizontally(by: rangeStepDays)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.headline.weight(.semibold))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private var primaryMonthLabel: String {
        monthYearText(for: visibleSections.first?.date ?? viewModel.initialScrollDate)
    }

    private var secondaryMonthLabel: String? {
        guard let firstDate = visibleSections.first?.date else {
            return nil
        }

        let firstComponents = calendar.dateComponents([.year, .month], from: firstDate)
        for section in visibleSections.dropFirst() {
            let sectionComponents = calendar.dateComponents([.year, .month], from: section.date)
            if firstComponents.year != sectionComponents.year || firstComponents.month != sectionComponents.month {
                return monthYearText(for: section.date)
            }
        }
        return nil
    }

    private var rangeStepDays: Int {
        rangeStepDaysPreference.clamped(to: 1...10)
    }

    private var visibleFirstDate: Date? {
        visibleSections.first?.date
    }

    private var visibleLastDate: Date? {
        visibleSections.last?.date
    }

    private var isTodayVisible: Bool {
        let today = calendar.startOfDay(for: Date())
        return visibleSections.contains { section in
            calendar.isDate(section.date, inSameDayAs: today)
        }
    }

    private var visibleSections: ArraySlice<WeekDaySection> {
        guard !viewModel.sections.isEmpty else { return [] }

        let fallbackViewportWidth = UIScreen.main.bounds.width
        let effectiveViewportWidth = horizontalViewportWidth > 0 ? horizontalViewportWidth : fallbackViewportWidth
        let visibleWidth = max(effectiveViewportWidth - timeColumnWidth, dayColumnWidth)
        let startIndex = max(Int(floor(horizontalScrollOffset / max(dayColumnWidth, 1))), 0)
        let endIndex = max(
            Int(ceil((horizontalScrollOffset + visibleWidth) / max(dayColumnWidth, 1))) - 1,
            startIndex
        )
        let clampedStart = min(startIndex, max(viewModel.sections.count - 1, 0))
        let clampedEnd = min(endIndex, max(viewModel.sections.count - 1, 0))
        return viewModel.sections[clampedStart...clampedEnd]
    }

    private func monthYearText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).capitalized
    }

    @ViewBuilder
    private func monthHeaderButton(text: String, date: Date?, alignment: Alignment) -> some View {
        Button {
            if let date {
                onWeekTitleTap?(date)
            }
        } label: {
            Text(text)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onWeekTitleTap == nil || date == nil)
    }

    private func restoreInitialHorizontalPositionIfNeeded() {
        guard !didRestoreInitialHorizontalPosition,
              let scrollView = horizontalScrollBridge.scrollView,
              let firstDate = viewModel.sections.first?.date else {
            return
        }

        let daysFromStart = dayDistance(from: firstDate, to: viewModel.initialScrollDate)
        let targetOffset = max(CGFloat(daysFromStart) * dayColumnWidth, 0)
        scrollView.setContentOffset(CGPoint(x: targetOffset, y: scrollView.contentOffset.y), animated: false)
        horizontalScrollOffset = targetOffset
        didRestoreInitialHorizontalPosition = true
        prefetchAroundVisibleRangeIfNeeded()
    }

    private func scrollHorizontally(by dayDelta: Int) {
        guard let scrollView = horizontalScrollBridge.scrollView else { return }

        let targetOffset = max(horizontalScrollOffset + CGFloat(dayDelta) * dayColumnWidth, 0)
        let maxOffset = max(scrollView.contentSize.width - scrollView.bounds.width, 0)
        let clampedOffset = min(targetOffset, maxOffset)
        scrollView.setContentOffset(CGPoint(x: clampedOffset, y: scrollView.contentOffset.y), animated: true)
        horizontalScrollOffset = clampedOffset

        if let startDate = visibleFirstDate {
            let targetStart = calendar.date(byAdding: .day, value: dayDelta, to: startDate) ?? startDate
            let targetEnd = calendar.date(byAdding: .day, value: max(dayDelta, 0), to: visibleLastDate ?? targetStart) ?? targetStart
            Task {
                await viewModel.ensureLoaded(covering: min(targetStart, targetEnd), endDate: max(targetStart, targetEnd))
            }
        }
    }

    private func prefetchAroundVisibleRangeIfNeeded() {
        guard let startDate = visibleFirstDate, let endDate = visibleLastDate else { return }

        Task {
            await viewModel.ensureLoaded(covering: startDate, endDate: endDate)
        }
    }

    private func dayDistance(from startDate: Date, to endDate: Date) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: startDate),
            to: calendar.startOfDay(for: endDate)
        ).day ?? 0
    }

    private func jumpToToday() {
        let today = calendar.startOfDay(for: Date())
        viewModel.showCurrentWeek()

        if let dayIndex = viewModel.sections.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: today) }),
           let horizontalScrollView = horizontalScrollBridge.scrollView {
            let targetOffsetX = max(CGFloat(dayIndex) * dayColumnWidth, 0)
            let maxOffsetX = max(horizontalScrollView.contentSize.width - horizontalScrollView.bounds.width, 0)
            let clampedOffsetX = min(targetOffsetX, maxOffsetX)
            horizontalScrollView.setContentOffset(
                CGPoint(x: clampedOffsetX, y: horizontalScrollView.contentOffset.y),
                animated: true
            )
            horizontalScrollOffset = clampedOffsetX
        }

        if let verticalScrollView = verticalScrollBridge.scrollView {
            let components = calendar.dateComponents([.hour, .minute], from: Date())
            let currentHour = CGFloat(components.hour ?? 0)
            let currentMinute = CGFloat(components.minute ?? 0)
            let targetOffsetY = ((currentHour * 60) + currentMinute) / 60 * hourHeight
            let maxOffsetY = max(verticalScrollView.contentSize.height - verticalScrollView.bounds.height, 0)
            let clampedOffsetY = min(max(targetOffsetY - hourHeight, 0), maxOffsetY)
            verticalScrollView.setContentOffset(
                CGPoint(x: verticalScrollView.contentOffset.x, y: clampedOffsetY),
                animated: true
            )
            timelineScrollOffset = clampedOffsetY
        }
    }

    private var minimumFittingHourHeight: CGFloat {
        max(verticalViewportHeight / 24, 1)
    }

    private func applyVerticalZoom(targetHourHeight: CGFloat, showFullDay: Bool) {
        let clampedHeight = targetHourHeight.clamped(to: minimumFittingHourHeight...maximumHourHeight)
        guard clampedHeight != hourHeight || showFullDay else { return }

        let viewportHeight = max(verticalViewportHeight, 0)
        let currentHourHeight = max(hourHeight, 1)
        let viewportCenter = viewportHeight / 2
        let currentOffset = verticalScrollBridge.scrollView?.contentOffset.y ?? timelineScrollOffset
        let anchorHour = if viewportHeight > 0 && !showFullDay {
            ((currentOffset + viewportCenter) / currentHourHeight).clamped(to: 0.0...23.0)
        } else {
            0.0
        }

        hourHeight = clampedHeight

        DispatchQueue.main.async {
            guard let scrollView = verticalScrollBridge.scrollView else { return }

            if showFullDay || viewportHeight <= 0 {
                scrollView.setContentOffset(
                    CGPoint(x: scrollView.contentOffset.x, y: 0),
                    animated: false
                )
                timelineScrollOffset = 0
                return
            }

            let maxOffset = max((clampedHeight * 24) - viewportHeight, 0)
            let targetOffset = ((anchorHour * clampedHeight) - viewportCenter).clamped(to: 0...maxOffset)
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: targetOffset),
                animated: false
            )
            timelineScrollOffset = targetOffset
        }
    }

    private func zoomInVertically() {
        applyVerticalZoom(targetHourHeight: hourHeight + 8, showFullDay: false)
    }

    private func zoomOutVertically() {
        applyVerticalZoom(targetHourHeight: hourHeight - 8, showFullDay: false)
    }

    private func zoomToFullDay() {
        applyVerticalZoom(targetHourHeight: minimumFittingHourHeight, showFullDay: true)
    }

    private var weeklyTimeline: some View {
        let timelineHeight = hourHeight * 24
        let displayedSections = viewModel.sections

        return ZStack(alignment: .topLeading) {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(displayedSections) { section in
                            WeeklyDayHeader(
                                section: section,
                                calendar: calendar,
                                width: dayColumnWidth,
                                onHeaderTap: { onDayHeaderTap?(section.date) }
                            )
                            .id(section.id)
                        }
                    }

                    ObservableScrollView(
                        bridge: verticalScrollBridge,
                        onScrollViewResolved: { _ in },
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
                                        previewEvent: activeEventInteraction?.previewEvent,
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
                                        onEventMoveStart: { event in
                                            beginEventMove(for: event, fallbackIndex: index)
                                        },
                                        onEventMoveChange: { event, translation in
                                            updateEventMove(for: event, translation: translation)
                                        },
                                        onEventResizeStart: { event in
                                            beginEventResize(for: event, fallbackIndex: index)
                                        },
                                        onEventResizeChange: { event, translation in
                                            updateEventResize(for: event, translation: translation)
                                        },
                                        onEventInteractionCommit: commitActiveEventInteraction,
                                        onEventInteractionCancel: cancelActiveEventInteraction
                                    )
                                }
                            }
                        },
                        onOffsetChange: { newOffset in
                            timelineScrollOffset = newOffset
                            refreshGuideStateIfNeeded()
                        },
                        onViewportHeightChange: { viewportHeight in
                            verticalViewportHeight = viewportHeight
                        }
                    )
                }
                .padding(.leading, timeColumnWidth)
            }
            .background(
                ScrollViewResolverView(axis: .horizontal) { scrollView in
                    horizontalScrollBridge.bind(to: scrollView) { offset in
                        horizontalScrollOffset = offset.x
                        horizontalViewportWidth = scrollView.bounds.width
                        prefetchAroundVisibleRangeIfNeeded()
                    }
                    horizontalViewportWidth = scrollView.bounds.width
                    restoreInitialHorizontalPositionIfNeeded()
                }
            )
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            horizontalViewportWidth = proxy.size.width
                        }
                        .onChange(of: proxy.size.width) { _, newWidth in
                            horizontalViewportWidth = newWidth
                        }
                }
            )

            VStack(spacing: 0) {
                TimeColumnHeaderPlaceholder(
                    width: timeColumnWidth,
                    height: dayHeaderHeight,
                    showsTodayButton: !isTodayVisible,
                    onTodayTap: jumpToToday
                )

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

            TwoAxisPinchCaptureView(
                onBegan: beginPinch,
                onChanged: updatePinch,
                onEnded: endPinch,
                onCancelled: endPinch
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 2) {
                zoomControlButton(systemName: "plus.magnifyingglass", action: zoomInVertically)
                zoomControlButton(systemName: "minus.magnifyingglass", action: zoomOutVertically)
                zoomControlButton(systemName: "arrow.up.left.and.down.right", action: zoomToFullDay)
            }
            .padding(.top, dayHeaderHeight + 10)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .zIndex(2)
        }
        .background(Color(uiColor: .systemBackground))
        .overlay(
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1),
            alignment: .top
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func zoomControlButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.primary.opacity(0.45))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private var deleteAction: (() -> Void)? {
        guard viewModel.editorDraft.id != nil else {
            return nil
        }
        return { viewModel.deleteCurrentEvent() }
    }

    private func beginEventMove(for event: CalendarEvent, fallbackIndex: Int) {
        let resolvedEvent = latestEvent(for: event.id) ?? event
        let resolvedDayIndex = dayIndex(for: resolvedEvent.startAt) ?? fallbackIndex
        activeEventInteraction = WeeklyEventInteraction(
            eventID: resolvedEvent.id,
            originalEvent: resolvedEvent,
            previewEvent: resolvedEvent,
            mode: .move(
                originalDayIndex: resolvedDayIndex,
                originalStartMinute: minuteOfDay(for: resolvedEvent.startAt)
            ),
            fallbackIndex: resolvedDayIndex
        )
    }

    private func updateEventMove(for event: CalendarEvent, translation: CGPoint) {
        guard var interaction = activeEventInteraction, interaction.eventID == event.id else { return }

        let originalDayIndex: Int
        let originalStartMinute: Int
        switch interaction.mode {
        case .move(let storedOriginalDayIndex, let storedOriginalStartMinute):
            originalDayIndex = storedOriginalDayIndex
            originalStartMinute = storedOriginalStartMinute
        case .resize:
            return
        }

        let dayShift = Int((translation.x / dayColumnWidth).rounded())
        let minuteShift = quantizedDeltaMinutes(from: translation.y)
        let targetDayIndex = (originalDayIndex + dayShift).clamped(to: 0...max(viewModel.sections.count - 1, 0))
        let baseEvent = interaction.originalEvent
        let maxStartMinute = max((24 * 60) - baseEvent.durationMinutes, 0)
        let startMinute = (originalStartMinute + minuteShift).clamped(to: 0...maxStartMinute)
        let startAt = date(for: targetDayIndex, minuteOfDay: startMinute)

        interaction.previewEvent = baseEvent.updating(startAt: startAt)
        interaction.fallbackIndex = targetDayIndex
        activeEventInteraction = interaction
    }

    private func beginEventResize(for event: CalendarEvent, fallbackIndex: Int) {
        let resolvedEvent = latestEvent(for: event.id) ?? event
        let preview = resolvedEvent.updating(durationMinutes: max(minimumEventDurationMinutes, resolvedEvent.durationMinutes))
        activeEventInteraction = WeeklyEventInteraction(
            eventID: resolvedEvent.id,
            originalEvent: resolvedEvent,
            previewEvent: preview,
            mode: .resize(originalDurationMinutes: resolvedEvent.durationMinutes),
            fallbackIndex: fallbackIndex
        )
    }

    private func updateEventResize(for event: CalendarEvent, translation: CGPoint) {
        guard var interaction = activeEventInteraction, interaction.eventID == event.id else { return }
        let originalDurationMinutes: Int
        switch interaction.mode {
        case .resize(let storedOriginalDurationMinutes):
            originalDurationMinutes = storedOriginalDurationMinutes
        case .move:
            return
        }

        let startMinute = minuteOfDay(for: interaction.previewEvent.startAt)
        let maxDuration = max((24 * 60) - startMinute, minimumEventDurationMinutes)
        let durationDelta = quantizedDeltaMinutes(from: translation.y)
        let duration = (originalDurationMinutes + durationDelta).clamped(to: minimumEventDurationMinutes...maxDuration)

        interaction.previewEvent = interaction.previewEvent.updating(durationMinutes: duration)
        activeEventInteraction = interaction
    }

    private func commitActiveEventInteraction() {
        guard let interaction = activeEventInteraction else { return }
        viewModel.applyInlineUpdate(from: interaction.originalEvent, to: interaction.previewEvent)
        activeEventInteraction = nil
    }

    private func cancelActiveEventInteraction() {
        activeEventInteraction = nil
    }

    private func quantizedMinute(from y: CGFloat, stepMinutes: Int) -> Int {
        let step = max(stepMinutes, 1)
        let visibleY = max(y, 0)
        let rawMinute = Int((visibleY / hourHeight) * 60)
        let quantizedMinute = (rawMinute / step) * step
        return quantizedMinute.clamped(to: 0...(24 * 60))
    }

    private func quantizedDeltaMinutes(from deltaY: CGFloat) -> Int {
        let step = max(manipulationSlotMinutes, 1)
        let rawMinuteDelta = Int(((deltaY / hourHeight) * 60).rounded())
        let snapped = Int((Double(rawMinuteDelta) / Double(step)).rounded()) * step
        return snapped
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

    private func latestEvent(for eventID: Int64) -> CalendarEvent? {
        viewModel.sections
            .flatMap(\.events)
            .first { $0.id == eventID }
    }

    private func dayIndex(for date: Date) -> Int? {
        viewModel.sections.firstIndex { section in
            calendar.isDate(section.date, inSameDayAs: date)
        }
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
        guard let scrollView = verticalScrollBridge.scrollView else { return }

        let currentOffset = scrollView.contentOffset.y
        let maxOffset = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
        let delta = direction == .up ? -step : step
        let targetOffset = max(0, min(currentOffset + delta, maxOffset))
        let appliedDelta = targetOffset - currentOffset

        guard abs(targetOffset - currentOffset) > .ulpOfOne else { return }

        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: targetOffset), animated: false)
        timelineScrollOffset = targetOffset
        if let interaction = guideInteraction {
            guideInteraction = WeeklyGuideInteraction(
                point: CGPoint(x: interaction.point.x, y: interaction.point.y + appliedDelta),
                fallbackIndex: interaction.fallbackIndex
            )
        }
        refreshGuideStateIfNeeded()
    }

    private func beginPinch(_ value: TwoAxisPinchValue) {
        guard guideInteraction == nil, activeEventInteraction == nil else { return }

        pinchInteraction = WeeklyPinchInteraction(
            startDayColumnWidth: dayColumnWidth,
            startHourHeight: hourHeight,
            initialHorizontalOffset: horizontalScrollBridge.scrollView?.contentOffset.x ?? 0,
            initialVerticalOffset: verticalScrollBridge.scrollView?.contentOffset.y ?? timelineScrollOffset,
            anchorPoint: value.center,
            initialSpan: value.span
        )
    }

    private func updatePinch(_ value: TwoAxisPinchValue) {
        guard let interaction = pinchInteraction else { return }

        let horizontalScale = pinchScale(
            current: value.span.width,
            initial: interaction.initialSpan.width,
            sensitivity: horizontalPinchSensitivity
        )
        let verticalScale = pinchScale(
            current: value.span.height,
            initial: interaction.initialSpan.height,
            sensitivity: verticalPinchSensitivity
        )

        let targetDayWidth = (interaction.startDayColumnWidth * horizontalScale)
            .clamped(to: minimumDayColumnWidth...maximumDayColumnWidth)
        let targetHourHeight = (interaction.startHourHeight * verticalScale)
            .clamped(to: minimumFittingHourHeight...maximumHourHeight)

        guard targetDayWidth != dayColumnWidth || targetHourHeight != hourHeight else { return }

        dayColumnWidth = targetDayWidth
        hourHeight = targetHourHeight

        let appliedHorizontalScale = targetDayWidth / interaction.startDayColumnWidth
        let appliedVerticalScale = targetHourHeight / interaction.startHourHeight
        let visibleX = max(interaction.anchorPoint.x - timeColumnWidth, 0)
        let visibleY = max(interaction.anchorPoint.y - dayHeaderHeight, 0)

        if let horizontalScrollView = horizontalScrollBridge.scrollView {
            let maxOffsetX = max(horizontalScrollView.contentSize.width - horizontalScrollView.bounds.width, 0)
            let targetOffsetX = ((interaction.initialHorizontalOffset + visibleX) * appliedHorizontalScale) - visibleX
            let clampedOffsetX = targetOffsetX.clamped(to: 0...maxOffsetX)
            horizontalScrollView.setContentOffset(
                CGPoint(x: clampedOffsetX, y: horizontalScrollView.contentOffset.y),
                animated: false
            )
        }

        if let verticalScrollView = verticalScrollBridge.scrollView {
            let maxOffsetY = max(verticalScrollView.contentSize.height - verticalScrollView.bounds.height, 0)
            let targetOffsetY = ((interaction.initialVerticalOffset + visibleY) * appliedVerticalScale) - visibleY
            let clampedOffsetY = targetOffsetY.clamped(to: 0...maxOffsetY)
            verticalScrollView.setContentOffset(
                CGPoint(x: verticalScrollView.contentOffset.x, y: clampedOffsetY),
                animated: false
            )
            timelineScrollOffset = clampedOffsetY

            if let guide = guideInteraction {
                guideInteraction = WeeklyGuideInteraction(
                    point: CGPoint(
                        x: guide.point.x,
                        y: guide.point.y + (clampedOffsetY - interaction.initialVerticalOffset)
                    ),
                    fallbackIndex: guide.fallbackIndex
                )
                refreshGuideStateIfNeeded()
            }
        }
    }

    private func endPinch() {
        pinchInteraction = nil
    }

    private func pinchScale(current: CGFloat, initial: CGFloat, sensitivity: CGFloat) -> CGFloat {
        guard current > 0, initial > 0 else { return 1 }
        return pow(current / initial, sensitivity)
    }
}

private struct WeeklyDayHeader: View {
    let section: WeekDaySection
    let calendar: Calendar
    let width: CGFloat
    let onHeaderTap: () -> Void

    var body: some View {
        Button(action: onHeaderTap) {
            VStack(spacing: 2) {
                Text(shortWeekday)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(dayNumber)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(section.isToday ? .primary : .primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: width, height: 52)
        .background(
            section.isToday
                ? Color.accentColor.opacity(0.16)
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
                    width: previewLayout.width,
                    height: previewLayout.height,
                    isActive: true,
                    longPressDuration: longPressDuration,
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
}

private struct WeeklyTimelineEventBlock: View {
    let event: CalendarEvent
    let calendar: Calendar
    let width: CGFloat
    let height: CGFloat
    let isActive: Bool
    let longPressDuration: TimeInterval
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
    let onMoveBegan: () -> Void
    let onMoveChanged: (CGPoint) -> Void
    let onMoveEnded: () -> Void
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
        private let onMoveBegan: () -> Void
        private let onMoveChanged: (CGPoint) -> Void
        private let onMoveEnded: () -> Void
        private let onMoveCancelled: () -> Void
        private var initialWindowPoint: CGPoint?

        init(
            onTap: @escaping () -> Void,
            onMoveBegan: @escaping () -> Void,
            onMoveChanged: @escaping (CGPoint) -> Void,
            onMoveEnded: @escaping () -> Void,
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
            let point = recognizer.location(in: nil)

            switch recognizer.state {
            case .began:
                initialWindowPoint = point
                onMoveBegan()
            case .changed:
                let translation = CGPoint(
                    x: point.x - (initialWindowPoint?.x ?? point.x),
                    y: point.y - (initialWindowPoint?.y ?? point.y)
                )
                onMoveChanged(translation)
            case .ended:
                onMoveEnded()
                initialWindowPoint = nil
            case .cancelled, .failed:
                onMoveCancelled()
                initialWindowPoint = nil
            default:
                break
            }
        }
    }
}

private struct PanCaptureView: UIViewRepresentable {
    let onBegan: () -> Void
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void
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
        private let onBegan: () -> Void
        private let onChanged: (CGPoint) -> Void
        private let onEnded: () -> Void
        private let onCancelled: () -> Void
        private var initialWindowPoint: CGPoint?

        init(
            onBegan: @escaping () -> Void,
            onChanged: @escaping (CGPoint) -> Void,
            onEnded: @escaping () -> Void,
            onCancelled: @escaping () -> Void
        ) {
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onCancelled = onCancelled
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let point = recognizer.location(in: nil)

            switch recognizer.state {
            case .began:
                initialWindowPoint = point
                onBegan()
            case .changed:
                let translation = CGPoint(
                    x: point.x - (initialWindowPoint?.x ?? point.x),
                    y: point.y - (initialWindowPoint?.y ?? point.y)
                )
                onChanged(translation)
            case .ended:
                onEnded()
                initialWindowPoint = nil
            case .cancelled, .failed:
                onCancelled()
                initialWindowPoint = nil
            default:
                break
            }
        }
    }
}

private struct ObservableScrollView<Content: View>: View {
    let bridge: ScrollViewBridge
    let onScrollViewResolved: (UIScrollView) -> Void
    let content: () -> Content
    let onOffsetChange: (CGFloat) -> Void
    let onViewportHeightChange: (CGFloat) -> Void

    init(
        bridge: ScrollViewBridge,
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
        .background(
            ScrollViewResolverView(axis: .vertical) { scrollView in
                bridge.bind(to: scrollView) { offset in
                    onOffsetChange(offset.y)
                }
                onScrollViewResolved(scrollView)
            }
        )
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
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

private struct WeeklyPinchInteraction {
    let startDayColumnWidth: CGFloat
    let startHourHeight: CGFloat
    let initialHorizontalOffset: CGFloat
    let initialVerticalOffset: CGFloat
    let anchorPoint: CGPoint
    let initialSpan: CGSize
}

private struct WeeklyEventInteraction {
    let eventID: Int64
    let originalEvent: CalendarEvent
    var previewEvent: CalendarEvent
    let mode: WeeklyEventInteractionMode
    var fallbackIndex: Int
}

private enum WeeklyEventInteractionMode {
    case move(originalDayIndex: Int, originalStartMinute: Int)
    case resize(originalDurationMinutes: Int)
}

private final class ScrollViewBridge {
    weak var scrollView: UIScrollView?
    private var displayLink: CADisplayLink?
    private var lastOffset: CGPoint = .zero
    private var onOffsetChange: ((CGPoint) -> Void)?

    func bind(to scrollView: UIScrollView, onOffsetChange: @escaping (CGPoint) -> Void) {
        self.onOffsetChange = onOffsetChange

        if self.scrollView !== scrollView {
            self.scrollView = scrollView
            lastOffset = scrollView.contentOffset
            startPollingIfNeeded()
        }

        onOffsetChange(scrollView.contentOffset)
    }

    deinit {
        displayLink?.invalidate()
    }

    @objc private func pollContentOffset() {
        guard let scrollView else { return }
        let offset = scrollView.contentOffset
        guard offset != lastOffset else { return }
        lastOffset = offset
        onOffsetChange?(offset)
    }

    private func startPollingIfNeeded() {
        guard displayLink == nil else { return }
        let displayLink = CADisplayLink(target: self, selector: #selector(pollContentOffset))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }
}

private struct ScrollViewResolverView: UIViewRepresentable {
    let axis: ScrollViewAxis
    let onResolve: (UIScrollView) -> Void

    func makeUIView(context: Context) -> UIView {
        ResolverUIView(axis: axis, onResolve: onResolve)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let resolverView = uiView as? ResolverUIView {
            resolverView.axis = axis
            resolverView.onResolve = onResolve
            resolverView.resolveIfNeeded()
        }
    }
}

private enum ScrollViewAxis {
    case horizontal
    case vertical
}

private final class ResolverUIView: UIView {
    var axis: ScrollViewAxis
    var onResolve: (UIScrollView) -> Void

    init(axis: ScrollViewAxis, onResolve: @escaping (UIScrollView) -> Void) {
        self.axis = axis
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
        guard let scrollView = resolvedWeeklyScrollView(axis: axis) else { return }
        onResolve(scrollView)
    }
}

private extension UIView {
    func resolvedWeeklyScrollView(axis: ScrollViewAxis) -> UIScrollView? {
        var root: UIView = self
        while let parent = root.superview {
            root = parent
        }

        let allScrollViews = root.allDescendantScrollViews()
        let candidates = allScrollViews.filter { scrollView in
            scrollView.layoutIfNeeded()
            switch axis {
            case .horizontal:
                return scrollView.contentSize.width > scrollView.bounds.width + 1 || scrollView.alwaysBounceHorizontal
            case .vertical:
                return scrollView.contentSize.height > scrollView.bounds.height + 1 || scrollView.alwaysBounceVertical
            }
        }

        if let bestMatch = candidates.max(by: { lhs, rhs in
            switch axis {
            case .horizontal:
                return (lhs.contentSize.width - lhs.bounds.width) < (rhs.contentSize.width - rhs.bounds.width)
            case .vertical:
                return (lhs.contentSize.height - lhs.bounds.height) < (rhs.contentSize.height - rhs.bounds.height)
            }
        }) {
            return bestMatch
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

private struct TwoAxisPinchValue {
    let center: CGPoint
    let span: CGSize
}

private struct TwoAxisPinchCaptureView: UIViewRepresentable {
    let onBegan: (TwoAxisPinchValue) -> Void
    let onChanged: (TwoAxisPinchValue) -> Void
    let onEnded: () -> Void
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
        let view = PinchGestureAttachmentView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onCancelled = onCancelled

        if let view = uiView as? PinchGestureAttachmentView {
            view.coordinator = context.coordinator
            view.attachIfNeeded()
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onBegan: (TwoAxisPinchValue) -> Void
        var onChanged: (TwoAxisPinchValue) -> Void
        var onEnded: () -> Void
        var onCancelled: () -> Void

        private lazy var recognizer: UIPinchGestureRecognizer = {
            let recognizer = UIPinchGestureRecognizer(
                target: self,
                action: #selector(handlePinch(_:))
            )
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            return recognizer
        }()

        private weak var attachedView: UIView?
        private weak var targetView: UIView?
        private var initialSpan: CGSize?

        init(
            onBegan: @escaping (TwoAxisPinchValue) -> Void,
            onChanged: @escaping (TwoAxisPinchValue) -> Void,
            onEnded: @escaping () -> Void,
            onCancelled: @escaping () -> Void
        ) {
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onCancelled = onCancelled
        }

        func attach(to view: UIView, targetView: UIView) {
            if attachedView === view {
                self.targetView = targetView
                return
            }
            attachedView?.removeGestureRecognizer(recognizer)
            view.addGestureRecognizer(recognizer)
            attachedView = view
            self.targetView = targetView
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard recognizer.numberOfTouches >= 2,
                  let view = recognizer.view,
                  let targetView else {
                if recognizer.state == .cancelled || recognizer.state == .failed {
                    onCancelled()
                    initialSpan = nil
                }
                return
            }

            let firstPointInHost = recognizer.location(ofTouch: 0, in: view)
            let secondPointInHost = recognizer.location(ofTouch: 1, in: view)
            let firstPoint = targetView.convert(firstPointInHost, from: view)
            let secondPoint = targetView.convert(secondPointInHost, from: view)
            let currentSpan = CGSize(
                width: abs(secondPoint.x - firstPoint.x),
                height: abs(secondPoint.y - firstPoint.y)
            )
            let center = CGPoint(
                x: (firstPoint.x + secondPoint.x) / 2,
                y: (firstPoint.y + secondPoint.y) / 2
            )

            guard targetView.bounds.insetBy(dx: -24, dy: -24).contains(center) else {
                if recognizer.state == .ended {
                    onEnded()
                    initialSpan = nil
                } else if recognizer.state == .cancelled || recognizer.state == .failed {
                    onCancelled()
                    initialSpan = nil
                }
                return
            }

            switch recognizer.state {
            case .began:
                initialSpan = currentSpan
                onBegan(
                    TwoAxisPinchValue(center: center, span: currentSpan)
                )
            case .changed:
                _ = initialSpan ?? currentSpan
                onChanged(
                    TwoAxisPinchValue(center: center, span: currentSpan)
                )
            case .ended:
                onEnded()
                initialSpan = nil
            case .cancelled, .failed:
                onCancelled()
                initialSpan = nil
            default:
                break
            }
        }
    }
}

private final class PinchGestureAttachmentView: UIView {
    weak var coordinator: TwoAxisPinchCaptureView.Coordinator?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        attachIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachIfNeeded()
    }

    func attachIfNeeded() {
        if let window {
            coordinator?.attach(to: window, targetView: self)
        }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension View {
    @ViewBuilder
    func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
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
