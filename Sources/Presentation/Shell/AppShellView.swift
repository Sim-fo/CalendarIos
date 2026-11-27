import SwiftUI

@MainActor
final class AppShellBadgeStore: ObservableObject {
    @Published private(set) var openTodoCount = 0
    @Published private(set) var overdueTrackers: [TrackerItem] = []

    private let featureRepository: GRDBFeatureRepository
    private var dismissedTrackerIds = Set<Int64>()

    init(featureRepository: GRDBFeatureRepository) {
        self.featureRepository = featureRepository
    }

    var overdueTrackerCount: Int {
        overdueTrackers.count
    }

    var nextPromptedOverdueTracker: TrackerItem? {
        overdueTrackers.first { !dismissedTrackerIds.contains($0.id) }
    }

    func refresh() async {
        do {
            let todos = try await featureRepository.fetchTodos()
            openTodoCount = todos.filter { !$0.isDone }.count

            let trackers = try await featureRepository.fetchTrackers()
            overdueTrackers = trackers.filter { $0.isOverdue() }

            let birthdays = try await featureRepository.fetchBirthdays()
            LocalNotificationService.rescheduleBirthdayReminders(birthdays: birthdays)
        } catch {
            // Keep last known badge counts
        }
    }

    func resetOverdueTracker(_ tracker: TrackerItem) async {
        try? await featureRepository.resetTracker(id: tracker.id, at: Date())
        NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
        await refresh()
    }

    func deleteOverdueTracker(_ tracker: TrackerItem) async {
        try? await featureRepository.deleteTracker(id: tracker.id)
        NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
        await refresh()
    }

    func dismissOverdueTrackerForSession(_ tracker: TrackerItem) {
        dismissedTrackerIds.insert(tracker.id)
        objectWillChange.send()
    }
}

struct AppShellView: View {
    let dependencies: CalendarDependencies
    @EnvironmentObject private var settings: AppSettingsStore
    @State private var selectedTab: RootTabSelection = .calendar
    @State private var selectedCalendarMode: CalendarMode = .week
    @State private var selectedCalendarDate: Date = Date()
    @StateObject private var weeklyViewModel: WeeklyViewModel
    @StateObject private var badgeStore: AppShellBadgeStore

    init(dependencies: CalendarDependencies) {
        self.dependencies = dependencies
        _weeklyViewModel = StateObject(
            wrappedValue: WeeklyViewModel(
                eventRepository: dependencies.eventRepository,
                eventTypeRepository: dependencies.eventRepository,
                featureRepository: dependencies.featureRepository
            )
        )
        _badgeStore = StateObject(
            wrappedValue: AppShellBadgeStore(featureRepository: dependencies.featureRepository)
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            CalendarHomeView(
                dependencies: dependencies,
                weeklyViewModel: weeklyViewModel,
                selectedMode: $selectedCalendarMode,
                selectedDate: $selectedCalendarDate
            )
            .tabItem {
                Label("tab.calendar", systemImage: "calendar")
            }
            .tag(RootTabSelection.calendar)

            ForEach(settings.customTabs) { feature in
                FeatureTabContainerView(feature: feature, dependencies: dependencies)
                    .tabItem {
                        Label(feature.shortTabTitleKey, systemImage: feature.systemImage)
                    }
                    .badge(badgeCount(for: feature))
                    .tag(RootTabSelection.feature(feature))
            }

            MoreMenuView(dependencies: dependencies)
                .tabItem {
                    Label("tab.more", systemImage: "square.grid.2x2")
                }
                .tag(RootTabSelection.more)
        }
        .onChange(of: settings.customTabs) { _, newTabs in
            if case .feature(let activeFeature) = selectedTab, !newTabs.contains(activeFeature) {
                selectedTab = .calendar
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab != .calendar {
                weeklyViewModel.isCopyModeEnabled = false
            }
        }
        .task {
            LocalNotificationService.requestAuthorizationIfNeeded()
            await badgeStore.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .calendarDataDidChange)) { _ in
            Task { await badgeStore.refresh() }
        }
        .alert(
            "trackers.overdue_alert_title",
            isPresented: Binding(
                get: { badgeStore.nextPromptedOverdueTracker != nil },
                set: { isPresented in
                    if !isPresented, let tracker = badgeStore.nextPromptedOverdueTracker {
                        badgeStore.dismissOverdueTrackerForSession(tracker)
                    }
                }
            ),
            presenting: badgeStore.nextPromptedOverdueTracker
        ) { tracker in
            Button("trackers.reset") {
                Task { await badgeStore.resetOverdueTracker(tracker) }
            }
            Button("common.delete", role: .destructive) {
                Task { await badgeStore.deleteOverdueTracker(tracker) }
            }
            Button("trackers.later", role: .cancel) {
                badgeStore.dismissOverdueTrackerForSession(tracker)
            }
        } message: { tracker in
            Text(
                String(
                    format: String(localized: "trackers.overdue_alert_message"),
                    tracker.name,
                    tracker.daysSinceReset(),
                    tracker.intervalDays
                )
            )
        }
    }

    private func badgeCount(for feature: AppFeatureTab) -> Int {
        switch feature {
        case .todo: return badgeStore.openTodoCount
        case .trackers: return badgeStore.overdueTrackerCount
        default: return 0
        }
    }
}

private struct FeatureTabContainerView: View {
    let feature: AppFeatureTab
    let dependencies: CalendarDependencies

    var body: some View {
        NavigationStack {
            switch feature {
            case .todo:
                TodoListView(repository: dependencies.featureRepository)
            case .trackers:
                TrackersListView(repository: dependencies.featureRepository)
            case .birthdays:
                BirthdaysListView(repository: dependencies.featureRepository)
            case .templates:
                TemplatesListView(
                    repository: dependencies.eventRepository,
                    optionRepository: dependencies.featureRepository
                )
            case .weeklyEvents:
                WeeklyEventsListView(dependencies: dependencies)
            case .clients:
                ClientsListView(repository: dependencies.featureRepository)
            case .mapMarkers:
                MapMarkersListView(repository: dependencies.featureRepository)
            }
        }
    }
}

private struct CalendarHomeView: View {
    let dependencies: CalendarDependencies
    @ObservedObject var weeklyViewModel: WeeklyViewModel
    @EnvironmentObject private var settings: AppSettingsStore
    @Binding var selectedMode: CalendarMode
    @Binding var selectedDate: Date

    private var calendar: Calendar {
        settings.effectiveCalendar
    }

    private var selectedYearBinding: Binding<Int> {
        Binding(
            get: { calendar.component(.year, from: selectedDate) },
            set: { newYear in
                let month = calendar.component(.month, from: selectedDate)
                let day = min(calendar.component(.day, from: selectedDate), 28)
                if let updated = calendar.date(from: DateComponents(year: newYear, month: month, day: day)) {
                    selectedDate = updated
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                switch selectedMode {
                case .day:
                    DailyView(
                        selectedDate: $selectedDate,
                        dependencies: dependencies,
                        onBackToWeekly: {
                            weeklyViewModel.focusDate(selectedDate)
                            selectedMode = .week
                        },
                        onEventTap: { event in
                            weeklyViewModel.openEditor(for: event)
                        }
                    )
                    .sheet(item: $weeklyViewModel.activeSheet) { sheet in
                        dailySheetView(for: sheet)
                    }
                case .week:
                    WeeklyView(
                        viewModel: weeklyViewModel,
                        calendar: calendar,
                        showsNavigationChrome: false,
                        onWeekTitleTap: { weekStart in
                            selectedDate = weekStart
                            selectedMode = .month
                        },
                        onDayHeaderTap: { date in
                            selectedDate = date
                            selectedMode = .day
                        }
                    )
                case .month:
                    MonthlyView(
                        targetDate: selectedDate,
                        dependencies: dependencies,
                        onSelectDay: { date in
                            selectedDate = date
                            weeklyViewModel.focusDate(date)
                            selectedMode = .week
                        },
                        onSelectYear: { year in
                            if let yearDate = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) {
                                selectedDate = yearDate
                            }
                            selectedMode = .year
                        }
                    )
                case .year:
                    YearlyView(
                        selectedYear: selectedYearBinding,
                        dependencies: dependencies,
                        onSelectMonth: { monthStart in
                            selectedDate = monthStart
                            selectedMode = .month
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedMode != .week {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            weeklyViewModel.focusDate(selectedDate)
                            selectedMode = .week
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("calendar.return_to_week")
                            }
                        }
                    }
                }

                ToolbarItem(placement: .principal) {
                    Menu {
                        ForEach(CalendarMode.allCases) { mode in
                            Button {
                                selectedMode = mode
                            } label: {
                                Label {
                                    Text(mode.titleKey)
                                } icon: {
                                    Image(systemName: mode == selectedMode ? "checkmark" : mode.systemImage)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(modeHeaderLabel)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                }

                if selectedMode == .week {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            weeklyViewModel.toggleCopyMode()
                        } label: {
                            Image(systemName: weeklyViewModel.isCopyModeEnabled ? "doc.on.doc.fill" : "doc.on.doc")
                                .foregroundStyle(
                                    weeklyViewModel.isCopyModeEnabled
                                        ? CalendarColor.copyModeAccent
                                        : Color.primary
                                )
                                .padding(6)
                                .background(
                                    weeklyViewModel.isCopyModeEnabled
                                        ? CalendarColor.copyModeAccent.opacity(0.18)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                        }
                        .accessibilityLabel("copy_mode.title")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dailySheetView(for sheet: WeeklyActiveSheet) -> some View {
        switch sheet {
        case .editTemplateEvent:
            TemplateEventEditView(
                draft: $weeklyViewModel.editorDraft,
                eventTypes: weeklyViewModel.eventTypes,
                featureRepository: dependencies.featureRepository,
                isSaving: weeklyViewModel.isSaving,
                onSave: { values in weeklyViewModel.saveEditor(optionValues: values) },
                onDelete: weeklyViewModel.deleteCurrentEvent,
                onEditTemplate: { tpl in weeklyViewModel.openTemplateEdit(tpl) },
                onCancel: weeklyViewModel.cancelEditor
            )
        case .editUniqueEvent:
            UniqueEventEditView(
                draft: $weeklyViewModel.editorDraft,
                isSaving: weeklyViewModel.isSaving,
                onSave: { weeklyViewModel.saveEditor() },
                onDelete: weeklyViewModel.editorDraft.id == nil ? nil : { weeklyViewModel.deleteCurrentEvent() },
                onCancel: weeklyViewModel.cancelEditor
            )
        case .editWeeklyRecurring(let item):
            WeeklyRecurringEventEditorView(
                initial: item,
                templates: weeklyViewModel.eventTypes,
                onSave: { templateId, customTitle, colorHex, reminder, slots in
                    await weeklyViewModel.saveWeeklyRecurring(
                        id: item.id,
                        templateId: templateId,
                        customTitle: customTitle,
                        customColorHex: colorHex,
                        reminderMinutes: reminder,
                        slots: slots
                    )
                },
                onDelete: {
                    await weeklyViewModel.deleteWeeklyRecurring(id: item.id)
                },
                onCancel: weeklyViewModel.cancelEditor
            )
        case .editTemplate(let template):
            TemplateEditorView(
                initialDraft: EventTypeDraft(eventType: template),
                existingEventCount: 0,
                optionRepository: dependencies.featureRepository,
                onSave: { draft in await weeklyViewModel.saveTemplateDraft(draft) },
                onDelete: nil,
                onCancel: weeklyViewModel.cancelEditor
            )
        default:
            EmptyView()
        }
    }

    private var modeHeaderLabel: String {
        switch selectedMode {
        case .day:
            return CalendarDateFormatter.shortDate(for: selectedDate, calendar: calendar)
        case .week:
            return String(localized: "tab.calendar")
        case .month:
            return CalendarDateFormatter.monthYear(for: selectedDate, calendar: calendar)
        case .year:
            return CalendarDateFormatter.year(for: selectedDate, calendar: calendar)
        }
    }
}
