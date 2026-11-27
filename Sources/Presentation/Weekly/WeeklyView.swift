import SwiftUI
import UIKit

struct WeeklyView: View {
    @ObservedObject var viewModel: WeeklyViewModel
    @EnvironmentObject private var settings: AppSettingsStore

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
    @State private var didApplyInitialDayWidth = false
    @State private var pinchInteraction: WeeklyPinchInteraction?
    @State private var didRestoreInitialHorizontalPosition = false
    @State private var verticalScrollBridge = ScrollViewBridge()
    @State private var horizontalScrollBridge = ScrollViewBridge()
    @State private var gestureCoordinator = WeeklyGestureCoordinator()

    private let timeColumnWidth: CGFloat = 58
    private let dayHeaderHeight: CGFloat = 52
    private let manipulationSlotMinutes = 15
    private let minimumEventDurationMinutes = 15
    private let longPressDuration = 0.38
    private let autoScrollEdgeThreshold: CGFloat = 64
    private let autoScrollStep: CGFloat = 10
    private let maximumHourHeight: CGFloat = 132
    private let minimumDayColumnWidth: CGFloat = 48
    private let maximumDayColumnWidth: CGFloat = 320
    private let horizontalPinchSensitivity: CGFloat = 0.8
    private let verticalPinchSensitivity: CGFloat = 0.9
    private let minimumPinchAxisSpan: CGFloat = 28

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

    private var selectionSlotMinutes: Int {
        settings.quantizationMinutes
    }

    private var rangeStepDays: Int {
        settings.scrollStepDays.clamped(to: 1...10)
    }

    private var activeTimePopup: (date: Date, duration: Int?)? {
        if let guideState {
            return (guideState.date, guideState.durationMinutes)
        }
        if let activeEventInteraction {
            switch activeEventInteraction.mode {
            case .move:
                return (activeEventInteraction.previewEvent.startAt, nil)
            case .resize:
                return (
                    activeEventInteraction.previewEvent.startAt,
                    activeEventInteraction.previewEvent.durationMinutes
                )
            }
        }
        return nil
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

            VStack(spacing: 8) {
                if viewModel.isCopyModeEnabled {
                    copyModeBanner
                }

                header

                if viewModel.isLoading && viewModel.sections.isEmpty {
                    ProgressView("weekly.loading")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    weeklyTimeline
                }
            }
            .padding(.top, 8)

            if let popup = activeTimePopup {
                VStack {
                    SelectionTimeHeaderView(
                        selectedDate: popup.date,
                        durationMinutes: popup.duration,
                        calendar: calendar,
                        use24hFormat: settings.use24hFormat
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .allowsHitTesting(false)

                    Spacer()
                }
                .transition(.opacity)
                .zIndex(10)
            }

            if let bannerMessage = viewModel.bannerMessage {
                VStack {
                    Spacer()
                    Text(bannerMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.bottom, 16)
                        .allowsHitTesting(false)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(12)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isCopyModeEnabled)
        .animation(.easeInOut(duration: 0.2), value: viewModel.bannerMessage)
        .if(showsNavigationChrome) { view in
            view
                .navigationTitle("calendar.mode.week")
                .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $viewModel.activeSheet) { sheet in
            activeSheetView(for: sheet)
        }
        .alert("common.error_title", isPresented: errorBinding) {
            Button("common.ok") {
                viewModel.dismissError()
            }
        } message: {
            Text(viewModel.errorMessage ?? String(localized: "common.unknown_error"))
        }
        .alert(
            "copy_mode.weekly_warning_title",
            isPresented: Binding(
                get: { viewModel.pendingCopyWeeklyWarningEvent != nil },
                set: { if !$0 { viewModel.pendingCopyWeeklyWarningEvent = nil } }
            )
        ) {
            Button("common.ok") {
                viewModel.confirmCopyWeeklyInstance()
            }
            Button("common.cancel", role: .cancel) {
                viewModel.pendingCopyWeeklyWarningEvent = nil
            }
        } message: {
            Text("copy_mode.weekly_warning_message")
        }
        .task {
            gestureCoordinator.onEnterZoomExclusive = {
                cancelSingleTouchInteractions()
            }
            gestureCoordinator.onSessionReset = {
                pinchInteraction = nil
            }
            viewModel.updateCalendar(settings.effectiveCalendar)
            viewModel.onAppear()
        }
        .onDisappear {
            cancelSingleTouchInteractions()
            pinchInteraction = nil
            gestureCoordinator.forceReset()
        }
        .onChange(of: settings.firstDayOfWeek) { _, _ in
            viewModel.updateCalendar(settings.effectiveCalendar)
        }
        .onChange(of: settings.visibleDays) { _, _ in
            applyVisibleDaysWidth(force: true)
        }
        .onChange(of: horizontalViewportWidth) { _, newWidth in
            if newWidth > 0 && !didApplyInitialDayWidth {
                applyVisibleDaysWidth(force: true)
                didApplyInitialDayWidth = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .calendarDataDidChange)) { _ in
            viewModel.refreshFromExternalChange()
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

    @ViewBuilder
    private func activeSheetView(for sheet: WeeklyActiveSheet) -> some View {
        switch sheet {
        case .createChooser(let selectedDate):
            EventCreateView(
                selectedDate: selectedDate,
                templates: viewModel.templatesWithCounts,
                lastSelectedTypeId: settings.lastSelectedEventTypeId,
                calendar: calendar,
                use24hFormat: settings.use24hFormat,
                onSelectTemplate: { template in
                    settings.lastSelectedEventTypeId = template.id
                    viewModel.createEvent(at: selectedDate, using: template)
                },
                onDeleteTemplate: { item, deleteLinked in
                    viewModel.deleteTemplate(item, deleteLinkedEvents: deleteLinked)
                },
                onCreateTemplate: {
                    viewModel.openTemplateCreate()
                },
                onCreateUnique: {
                    viewModel.openUniqueEventCreate(at: selectedDate)
                },
                onCancel: {
                    viewModel.cancelEditor()
                }
            )
        case .editTemplateEvent:
            TemplateEventEditView(
                draft: $viewModel.editorDraft,
                eventTypes: viewModel.eventTypes,
                featureRepository: viewModel.featureRepository,
                isSaving: viewModel.isSaving,
                onSave: { values in
                    viewModel.saveEditor(optionValues: values)
                },
                onDelete: viewModel.deleteCurrentEvent,
                onEditTemplate: { template in
                    viewModel.openTemplateEdit(template)
                },
                onCancel: viewModel.cancelEditor
            )
        case .editUniqueEvent:
            UniqueEventEditView(
                draft: $viewModel.editorDraft,
                isSaving: viewModel.isSaving,
                onSave: { viewModel.saveEditor() },
                onDelete: viewModel.editorDraft.id == nil ? nil : { viewModel.deleteCurrentEvent() },
                onCancel: viewModel.cancelEditor
            )
        case .createTemplate:
            TemplateEditorView(
                initialDraft: EventTypeDraft.empty(),
                existingEventCount: 0,
                optionRepository: viewModel.featureRepository,
                onSave: { draft in
                    await viewModel.saveTemplateDraft(draft)
                },
                onDelete: nil,
                onCancel: viewModel.cancelEditor
            )
        case .editTemplate(let template):
            let linkedCount = viewModel.templatesWithCounts.first(where: { $0.id == template.id })?.eventCount ?? 0
            TemplateEditorView(
                initialDraft: EventTypeDraft(eventType: template),
                existingEventCount: linkedCount,
                optionRepository: viewModel.featureRepository,
                onSave: { draft in
                    await viewModel.saveTemplateDraft(draft)
                },
                onDelete: { deleteLinked in
                    if let item = viewModel.templatesWithCounts.first(where: { $0.id == template.id }) {
                        viewModel.deleteTemplate(item, deleteLinkedEvents: deleteLinked)
                    }
                    viewModel.cancelEditor()
                },
                onCancel: viewModel.cancelEditor
            )
        case .editWeeklyRecurring(let item):
            WeeklyRecurringEventEditorView(
                initial: item,
                templates: viewModel.eventTypes,
                onSave: { templateId, customTitle, colorHex, reminder, slots in
                    await viewModel.saveWeeklyRecurring(
                        id: item.id,
                        templateId: templateId,
                        customTitle: customTitle,
                        customColorHex: colorHex,
                        reminderMinutes: reminder,
                        slots: slots
                    )
                },
                onDelete: {
                    await viewModel.deleteWeeklyRecurring(id: item.id)
                },
                onCancel: viewModel.cancelEditor
            )
        }
    }

    private var copyModeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.doc.fill")
                .font(.subheadline)
                .foregroundStyle(CalendarColor.copyModeAccent)

            if let selected = viewModel.selectedCopyEvent {
                Text(String(format: String(localized: "copy_mode.banner_selected"), selected.title))
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            } else {
                Text("copy_mode.select_event_hint")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button("common.done") {
                viewModel.isCopyModeEnabled = false
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(CalendarColor.copyModeAccent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(CalendarColor.copyModeAccent.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
    }

    private var header: some View {
        ZStack {
            HStack {
                monthHeaderButton(
                    text: primaryMonthLabel,
                    date: visibleFirstDate
                )

                Spacer(minLength: 0)

                if let secondaryMonthLabel {
                    monthHeaderButton(
                        text: secondaryMonthLabel,
                        date: visibleLastDate
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private var primaryMonthLabel: String {
        CalendarDateFormatter.monthYear(for: visibleSections.first?.date ?? viewModel.initialScrollDate, calendar: calendar)
    }

    private var secondaryMonthLabel: String? {
        guard let firstDate = visibleSections.first?.date else {
            return nil
        }

        let firstComponents = calendar.dateComponents([.year, .month], from: firstDate)
        for section in visibleSections.dropFirst() {
            let sectionComponents = calendar.dateComponents([.year, .month], from: section.date)
            if firstComponents.year != sectionComponents.year || firstComponents.month != sectionComponents.month {
                return CalendarDateFormatter.monthYear(for: section.date, calendar: calendar)
            }
        }
        return nil
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

    private func applyVisibleDaysWidth(force: Bool) {
        let viewport = horizontalViewportWidth > 0 ? horizontalViewportWidth : UIScreen.main.bounds.width
        let availableWidth = max(viewport - timeColumnWidth, 1)
        let targetWidth = (availableWidth / CGFloat(max(settings.visibleDays, 1)))
            .clamped(to: minimumDayColumnWidth...maximumDayColumnWidth)
        if force || abs(dayColumnWidth - targetWidth) > 0.5 {
            dayColumnWidth = targetWidth
        }
    }

    @ViewBuilder
    private func monthHeaderButton(text: String, date: Date?) -> some View {
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

        if !didApplyInitialDayWidth && scrollView.bounds.width > 0 {
            horizontalViewportWidth = scrollView.bounds.width
            applyVisibleDaysWidth(force: true)
            didApplyInitialDayWidth = true
        }

        let targetStart = settings.showWeekFromCurrentDay
            ? calendar.startOfDay(for: Date())
            : viewModel.initialScrollDate
        let daysFromStart = dayDistance(from: firstDate, to: targetStart)
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
        let anchorHour: CGFloat = if viewportHeight > 0 && !showFullDay {
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
                                todayHighlightColor: settings.todayHighlightColor,
                                onHeaderTap: {
                                    guard gestureCoordinator.canHandleSingleTouch else { return }
                                    onDayHeaderTap?(section.date)
                                }
                            )
                            .id(section.id)
                        }
                    }

                    ObservableScrollView(
                        bridge: verticalScrollBridge,
                        onScrollViewResolved: { scrollView in
                            gestureCoordinator.bindScrollViews(horizontal: nil, vertical: scrollView)
                        },
                        content: {
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(Array(displayedSections.enumerated()), id: \.element.id) { index, section in
                                    WeeklyTimelineDayColumn(
                                        section: section,
                                        sectionIndex: index,
                                        dayCount: displayedSections.count,
                                        calendar: calendar,
                                        use24hFormat: settings.use24hFormat,
                                        width: dayColumnWidth,
                                        hourHeight: hourHeight,
                                        timelineHeight: timelineHeight,
                                        selectionSlotMinutes: selectionSlotMinutes,
                                        longPressDuration: longPressDuration,
                                        isLongPressEnabled: viewModel.isLongPressEnabled,
                                        gestureCoordinator: gestureCoordinator,
                                        guideState: guideState,
                                        guideHighlightColor: settings.guideHighlightColor,
                                        todayHighlightColor: settings.todayHighlightColor,
                                        scrollOffsetY: timelineScrollOffset,
                                        activeEventID: activeEventInteraction?.eventID,
                                        selectedCopyEventID: viewModel.selectedCopyEvent?.id,
                                        previewEvent: activeEventInteraction?.previewEvent,
                                        onGuideStart: { point in
                                            guard !gestureCoordinator.isZoomExclusive else { return }
                                            guideInteraction = WeeklyGuideInteraction(point: point, fallbackIndex: index)
                                            let nextGuide = makeGuideState(from: point, fallbackIndex: index)
                                            triggerHaptic(.medium)
                                            withAnimation(.easeOut(duration: 0.12)) {
                                                guideState = nextGuide
                                            }
                                        },
                                        onGuideChange: { point in
                                            guard !gestureCoordinator.isZoomExclusive, guideInteraction != nil else { return }
                                            guideInteraction = WeeklyGuideInteraction(point: point, fallbackIndex: index)
                                            let nextGuide = makeGuideState(from: point, fallbackIndex: index)
                                            if nextGuide != guideState {
                                                triggerHaptic(.light)
                                                guideState = nextGuide
                                            }
                                        },
                                        onGuideCommit: { point in
                                            guard !gestureCoordinator.isZoomExclusive, guideInteraction != nil else {
                                                cancelSingleTouchInteractions()
                                                return
                                            }
                                            guideInteraction = WeeklyGuideInteraction(point: point, fallbackIndex: index)
                                            let quantized = makeGuideState(from: point, fallbackIndex: index)
                                            guideInteraction = nil
                                            withAnimation(.easeOut(duration: 0.12)) {
                                                guideState = nil
                                            }
                                            viewModel.handleLongPressCommit(
                                                at: quantized.date,
                                                quantizationMinutes: selectionSlotMinutes
                                            )
                                        },
                                        onGuideCancel: {
                                            guideInteraction = nil
                                            withAnimation(.easeOut(duration: 0.12)) {
                                                guideState = nil
                                            }
                                        },
                                        onEventTap: { event in
                                            guard gestureCoordinator.canHandleSingleTouch else { return }
                                            viewModel.handleEventTap(event)
                                        },
                                        onEventMoveStart: { event in
                                            guard !gestureCoordinator.isZoomExclusive else { return }
                                            triggerHaptic(.medium)
                                            beginEventMove(for: event, fallbackIndex: index)
                                        },
                                        onEventMoveChange: { event, translation in
                                            guard !gestureCoordinator.isZoomExclusive else { return }
                                            updateEventMove(for: event, translation: translation)
                                        },
                                        onEventResizeStart: { event in
                                            guard !gestureCoordinator.isZoomExclusive else { return }
                                            triggerHaptic(.light)
                                            beginEventResize(for: event, fallbackIndex: index)
                                        },
                                        onEventResizeChange: { event, translation in
                                            guard !gestureCoordinator.isZoomExclusive else { return }
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
                    .accessibilityIdentifier("weekly.verticalScroll")
                }
                .padding(.leading, timeColumnWidth)
                .background(
                    ScrollViewResolverView(axis: .horizontal) { scrollView in
                        gestureCoordinator.bindScrollViews(horizontal: scrollView, vertical: nil)
                        horizontalScrollBridge.bind(to: scrollView) { offset in
                            horizontalScrollOffset = offset.x
                            if horizontalViewportWidth != scrollView.bounds.width {
                                horizontalViewportWidth = scrollView.bounds.width
                            }
                            prefetchAroundVisibleRangeIfNeeded()
                        }
                        if horizontalViewportWidth != scrollView.bounds.width {
                            horizontalViewportWidth = scrollView.bounds.width
                        }
                        restoreInitialHorizontalPositionIfNeeded()
                    }
                )
            }
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

                GeometryReader { _ in
                    TimeColumnView(
                        calendar: calendar,
                        use24hFormat: settings.use24hFormat,
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
                gestureCoordinator: gestureCoordinator,
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

            Text(
                verbatim: "hour=\(Int(hourHeight.rounded())),day=\(Int(dayColumnWidth.rounded())),scrollY=\(Int(timelineScrollOffset.rounded())),scrollX=\(Int(horizontalScrollOffset.rounded()))"
            )
            .font(.system(size: 1))
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityIdentifier("weekly.metrics")
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

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard settings.allowHapticFeedback else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
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

    private func beginEventMove(for event: CalendarEvent, fallbackIndex: Int) {
        guard !viewModel.isCopyModeEnabled, !event.isRecurringInstance else { return }
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

        if startAt != interaction.previewEvent.startAt {
            triggerHaptic(.light)
        }
        interaction.previewEvent = baseEvent.updating(startAt: startAt)
        interaction.fallbackIndex = targetDayIndex
        activeEventInteraction = interaction
    }

    private func beginEventResize(for event: CalendarEvent, fallbackIndex: Int) {
        guard !viewModel.isCopyModeEnabled, !event.isRecurringInstance else { return }
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

        if duration != interaction.previewEvent.durationMinutes {
            triggerHaptic(.light)
        }
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

    private func quantizedDeltaMinutes(from deltaY: CGFloat) -> Int {
        let step = max(manipulationSlotMinutes, 1)
        let rawMinuteDelta = Int(((deltaY / hourHeight) * 60).rounded())
        return Int((Double(rawMinuteDelta) / Double(step)).rounded()) * step
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

        let step = max(selectionSlotMinutes, 1)
        let visibleY = max(point.y, 0)
        let maxMinutes = 24 * 60 - step
        let rawMinutes = Int((visibleY / hourHeight) * 60)
        let quantizedMinutes = ((rawMinutes / step) * step).clamped(to: 0...maxMinutes)
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

    private func cancelSingleTouchInteractions() {
        guideInteraction = nil
        if guideState != nil {
            withAnimation(.easeOut(duration: 0.1)) {
                guideState = nil
            }
        }
        activeEventInteraction = nil
    }

    private func beginPinch(_ value: TwoAxisPinchValue) {
        cancelSingleTouchInteractions()

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

        let horizontalScale: CGFloat
        let verticalScale: CGFloat
        if interaction.initialSpan.width < minimumPinchAxisSpan &&
            interaction.initialSpan.height < minimumPinchAxisSpan {
            let initialDiag = max(hypot(interaction.initialSpan.width, interaction.initialSpan.height), 12)
            let currentDiag = max(hypot(value.span.width, value.span.height), 12)
            horizontalScale = pow(currentDiag / initialDiag, horizontalPinchSensitivity)
            verticalScale = pow(currentDiag / initialDiag, verticalPinchSensitivity)
        } else {
            horizontalScale = pinchScale(
                current: value.span.width,
                initial: interaction.initialSpan.width,
                sensitivity: horizontalPinchSensitivity
            )
            verticalScale = pinchScale(
                current: value.span.height,
                initial: interaction.initialSpan.height,
                sensitivity: verticalPinchSensitivity
            )
        }

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
        guard initial >= minimumPinchAxisSpan, current > 0 else { return 1 }
        return pow(current / initial, sensitivity)
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
