import Foundation

enum WeeklyActiveSheet: Identifiable, Equatable {
    case createChooser(Date)
    case editTemplateEvent
    case editUniqueEvent
    case createTemplate
    case editTemplate(EventType)
    case editWeeklyRecurring(WeeklyRecurringItem)

    var id: String {
        switch self {
        case .createChooser(let date):
            return "createChooser-\(date.millisecondsSince1970)"
        case .editTemplateEvent:
            return "editTemplateEvent"
        case .editUniqueEvent:
            return "editUniqueEvent"
        case .createTemplate:
            return "createTemplate"
        case .editTemplate(let type):
            return "editTemplate-\(type.id)"
        case .editWeeklyRecurring(let item):
            return "editWeekly-\(item.id)"
        }
    }
}

@MainActor
final class WeeklyViewModel: ObservableObject {
    @Published private(set) var weekStart: Date
    @Published private(set) var weekTitle: String = ""
    @Published private(set) var sections: [WeekDaySection] = []
    @Published private(set) var eventTypes: [EventType] = []
    @Published private(set) var templatesWithCounts: [EventTypeWithCount] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?
    @Published var editorDraft: EventDraft
    @Published var activeSheet: WeeklyActiveSheet?

    // Copy mode state (1-to-1 with Android CopyModeManager)
    @Published var isCopyModeEnabled = false {
        didSet {
            if !isCopyModeEnabled {
                selectedCopyEvent = nil
            }
        }
    }
    @Published private(set) var selectedCopyEvent: CalendarEvent?
    @Published var pendingCopyWeeklyWarningEvent: CalendarEvent?
    @Published private(set) var bannerMessage: String?

    private let eventRepository: any EventRepository
    private let eventTypeRepository: any EventTypeRepository
    let featureRepository: GRDBFeatureRepository?
    private var calendar: Calendar
    private let initialPastDays = 28
    private let initialFutureDays = 42
    private let preloadPaddingDays = 14
    private var hasLoaded = false
    private var eventBeingEditedID: Int64?
    private var latestInlineMutationID = 0
    private var loadedStartDate: Date
    private var loadedEndDateExclusive: Date
    private var bannerDismissTask: Task<Void, Never>?

    init(
        eventRepository: any EventRepository,
        eventTypeRepository: any EventTypeRepository,
        featureRepository: GRDBFeatureRepository? = nil,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) {
        self.eventRepository = eventRepository
        self.eventTypeRepository = eventTypeRepository
        self.featureRepository = featureRepository
        self.calendar = calendar

        let normalizedReferenceDate = calendar.startOfDay(for: referenceDate)
        let initialWeekStart = calendar.startOfWeek(containing: normalizedReferenceDate)

        self.weekStart = initialWeekStart
        self.editorDraft = EventDraft.empty(on: normalizedReferenceDate, calendar: calendar)
        self.weekTitle = CalendarDateFormatter.weekTitle(for: initialWeekStart, calendar: calendar)
        self.loadedStartDate = calendar.date(byAdding: .day, value: -initialPastDays, to: initialWeekStart) ?? initialWeekStart
        self.loadedEndDateExclusive = calendar.date(byAdding: .day, value: initialFutureDays + 1, to: initialWeekStart) ?? initialWeekStart
    }

    func updateCalendar(_ newCalendar: Calendar) {
        guard calendar.firstWeekday != newCalendar.firstWeekday else { return }
        calendar = newCalendar
        weekStart = calendar.startOfWeek(containing: weekStart)
        weekTitle = CalendarDateFormatter.weekTitle(for: weekStart, calendar: calendar)
        Task {
            await reloadLoadedRange()
        }
    }

    func onAppear() {
        guard !hasLoaded else { return }
        hasLoaded = true

        Task {
            await loadInitialState()
        }
    }

    func refreshFromExternalChange() {
        guard hasLoaded else { return }
        Task {
            await reloadLoadedRange()
        }
    }

    func focusDate(_ date: Date) {
        weekStart = calendar.startOfWeek(containing: date)
        weekTitle = CalendarDateFormatter.weekTitle(for: weekStart, calendar: calendar)
        Task {
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            await ensureLoaded(covering: weekStart, endDate: weekEnd)
        }
    }

    func showPreviousWeek() {
        shiftWeek(by: -7)
    }

    func showNextWeek() {
        shiftWeek(by: 7)
    }

    func showCurrentWeek() {
        focusDate(Date())
    }

    var initialScrollDate: Date {
        weekStart
    }

    var isLongPressEnabled: Bool {
        !isCopyModeEnabled || selectedCopyEvent != nil
    }

    // MARK: - Copy Mode

    func toggleCopyMode() {
        isCopyModeEnabled.toggle()
        if isCopyModeEnabled {
            showBanner(String(localized: "copy_mode.select_event_hint"))
        } else {
            bannerMessage = nil
        }
    }

    func handleEventTap(_ event: CalendarEvent) {
        if isCopyModeEnabled {
            if event.isRecurringInstance {
                pendingCopyWeeklyWarningEvent = event
                return
            }
            selectedCopyEvent = event
            showBanner(String(localized: "copy_mode.ready_to_copy"))
            return
        }
        openEditor(for: event)
    }

    func confirmCopyWeeklyInstance() {
        guard let event = pendingCopyWeeklyWarningEvent else { return }
        pendingCopyWeeklyWarningEvent = nil
        selectedCopyEvent = event
        showBanner(String(localized: "copy_mode.ready_to_copy"))
    }

    func handleLongPressCommit(at date: Date, quantizationMinutes: Int) {
        let quantized = quantizedDate(date, stepMinutes: quantizationMinutes)

        if isCopyModeEnabled {
            guard let source = selectedCopyEvent else { return }
            copyEvent(source, to: quantized)
            return
        }

        activeSheet = .createChooser(quantized)
    }

    private func copyEvent(_ source: CalendarEvent, to startDate: Date) {
        Task {
            do {
                let draft = EventDraft(
                    id: nil,
                    eventTypeId: source.eventTypeId,
                    customTitle: source.customTitle ?? "",
                    customColorHex: source.customColorHex,
                    startAt: startDate,
                    durationMinutes: source.durationMinutes,
                    reminderMinutes: source.reminderMinutes,
                    note: source.note ?? "",
                    audioNotePath: nil,
                    selectedOptionId: source.isRecurringInstance ? nil : source.selectedOptionId,
                    selectedOptionName: source.isRecurringInstance ? nil : source.selectedOptionName
                )
                _ = try await eventRepository.upsert(draft)
                await reloadLoadedRange()
                NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
                showBanner(String(localized: "copy_mode.event_copied"))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Creation & Editing

    func createEvent(at date: Date, using template: EventType) {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                let draft = EventDraft(
                    id: nil,
                    eventTypeId: template.id,
                    customTitle: "",
                    customColorHex: nil,
                    startAt: date,
                    durationMinutes: template.defaultDurationMinutes,
                    reminderMinutes: template.notifyBeforeMinutes,
                    note: ""
                )
                let created = try await eventRepository.upsert(draft)
                LocalNotificationService.scheduleEventReminder(for: created)
                activeSheet = nil
                await reloadLoadedRange()
                NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    func openUniqueEventCreate(at date: Date) {
        eventBeingEditedID = nil
        editorDraft = EventDraft(
            id: nil,
            eventTypeId: nil,
            customTitle: "",
            customColorHex: CalendarColor.defaultEventHex,
            startAt: date,
            durationMinutes: 60,
            reminderMinutes: 0,
            note: ""
        )
        activeSheet = .editUniqueEvent
    }

    func openTemplateCreate() {
        activeSheet = .createTemplate
    }

    func openTemplateEdit(_ template: EventType) {
        activeSheet = .editTemplate(template)
    }

    func openEditor(for event: CalendarEvent) {
        if let recurringId = event.recurringEventId {
            Task {
                if let item = try? await featureRepository?.fetchWeeklyEvent(id: recurringId) {
                    activeSheet = .editWeeklyRecurring(item)
                }
            }
            return
        }

        eventBeingEditedID = event.id
        if let typeId = event.eventTypeId, eventTypes.contains(where: { $0.id == typeId }) {
            editorDraft = EventDraft(
                id: event.id,
                eventTypeId: typeId,
                customTitle: event.customTitle ?? "",
                customColorHex: event.customColorHex,
                startAt: event.startAt,
                durationMinutes: event.durationMinutes,
                reminderMinutes: event.reminderMinutes,
                note: event.note ?? "",
                audioNotePath: event.audioNotePath,
                selectedOptionId: event.selectedOptionId,
                selectedOptionName: event.selectedOptionName
            )
            activeSheet = .editTemplateEvent
        } else {
            editorDraft = EventDraft(event: event)
            editorDraft.eventTypeId = nil
            activeSheet = .editUniqueEvent
        }
    }

    func cancelEditor() {
        activeSheet = nil
        eventBeingEditedID = nil
    }

    func dismissError() {
        errorMessage = nil
    }

    func saveEditor(optionValues: [EventOptionValue] = []) {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                var draftToSave = editorDraft
                draftToSave.id = eventBeingEditedID

                if draftToSave.eventTypeId == nil && draftToSave.customTitle.nilIfBlank == nil {
                    let existingNames = try await eventRepository.fetchUniqueEventTitles()
                    draftToSave.customTitle = NameGenerator.generateNextName(existingNames: existingNames)
                }

                let saved = try await eventRepository.upsert(draftToSave)
                if let featureRepository, saved.eventTypeId != nil {
                    try await featureRepository.saveOptionValues(forEventId: saved.id, values: optionValues)
                }
                LocalNotificationService.scheduleEventReminder(for: saved)
                cancelEditor()
                await reloadLoadedRange()
                NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    func deleteCurrentEvent() {
        guard let eventID = eventBeingEditedID else { return }
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await eventRepository.delete(id: eventID)
                LocalNotificationService.cancelEventReminder(eventId: eventID)
                if selectedCopyEvent?.id == eventID {
                    selectedCopyEvent = nil
                }
                cancelEditor()
                await reloadLoadedRange()
                NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    func saveTemplateDraft(_ draft: EventTypeDraft) async -> Bool {
        errorMessage = nil
        do {
            var resolved = draft
            let trimmed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                let existing = try await eventTypeRepository.fetchEventTypes().map(\.title)
                resolved.title = NameGenerator.generateNextName(existingNames: existing)
            } else {
                let isUnique = try await eventTypeRepository.isEventTypeTitleUnique(trimmed, excludingId: draft.id)
                guard isUnique else {
                    errorMessage = String(localized: "templates.error.duplicate_name")
                    return false
                }
                resolved.title = trimmed
            }

            _ = try await eventTypeRepository.upsertEventType(resolved)
            activeSheet = nil
            await reloadLoadedRange()
            NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteTemplate(_ item: EventTypeWithCount, deleteLinkedEvents: Bool) {
        Task {
            do {
                try await eventTypeRepository.deleteEventType(id: item.id, deleteLinkedEvents: deleteLinkedEvents)
                await reloadLoadedRange()
                NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func saveWeeklyRecurring(
        id: Int64,
        templateId: Int64?,
        customTitle: String?,
        customColorHex: Int?,
        reminderMinutes: Int,
        slots: [WeeklyRecurringSlot]
    ) async {
        guard let featureRepository else { return }
        do {
            _ = try await featureRepository.upsertWeeklyEvent(
                id: id,
                templateId: templateId,
                customTitle: customTitle,
                customColorHex: customColorHex,
                reminderMinutes: reminderMinutes,
                slots: slots
            )
            activeSheet = nil
            await reloadLoadedRange()
            NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteWeeklyRecurring(id: Int64) async {
        guard let featureRepository else { return }
        do {
            try await featureRepository.deleteWeeklyEvent(id: id)
            activeSheet = nil
            await reloadLoadedRange()
            NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyInlineUpdate(from original: CalendarEvent, to updated: CalendarEvent) {
        guard !original.isRecurringInstance else { return }
        guard original.startAt != updated.startAt || original.durationMinutes != updated.durationMinutes else {
            return
        }

        errorMessage = nil
        applyOptimisticUpdate(updated, replacing: original.id)
        latestInlineMutationID += 1
        let mutationID = latestInlineMutationID

        Task {
            do {
                var draft = EventDraft(event: original)
                draft.startAt = updated.startAt
                draft.durationMinutes = updated.durationMinutes
                if original.eventTypeId != nil {
                    draft.customTitle = original.customTitle ?? ""
                    draft.customColorHex = original.customColorHex
                }
                let saved = try await eventRepository.upsert(draft)
                LocalNotificationService.scheduleEventReminder(for: saved)
                guard mutationID == latestInlineMutationID else { return }
                await reloadLoadedRange()
                NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
            } catch {
                guard mutationID == latestInlineMutationID else { return }
                errorMessage = error.localizedDescription
                await reloadLoadedRange()
            }
        }
    }

    func ensureLoaded(covering startDate: Date, endDate: Date) async {
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedEnd = calendar.startOfDay(for: endDate)
        let paddedStart = calendar.date(byAdding: .day, value: -preloadPaddingDays, to: normalizedStart) ?? normalizedStart
        let paddedEndExclusive = calendar.date(byAdding: .day, value: preloadPaddingDays + 1, to: normalizedEnd) ?? normalizedEnd

        guard paddedStart < loadedStartDate || paddedEndExclusive > loadedEndDateExclusive else {
            return
        }

        loadedStartDate = min(loadedStartDate, paddedStart)
        loadedEndDateExclusive = max(loadedEndDateExclusive, paddedEndExclusive)
        await reloadLoadedRange()
    }

    func loadInitialState() async {
        isLoading = true
        errorMessage = nil

        do {
            try await eventRepository.seedIfNeeded(referenceDate: weekStart)
            await reloadLoadedRange()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func reloadLoadedRange() async {
        do {
            templatesWithCounts = try await eventTypeRepository.fetchEventTypesWithCounts()
            eventTypes = templatesWithCounts.map(\.eventType)
            let interval = DateInterval(start: loadedStartDate, end: loadedEndDateExclusive)
            let events = try await eventRepository.events(in: interval)
            let grouped = Dictionary(grouping: events) { event in
                calendar.startOfDay(for: event.startAt)
            }

            let allTrackers = (try? await featureRepository?.fetchTrackers()) ?? []
            let allBirthdays = (try? await featureRepository?.fetchBirthdays()) ?? []

            sections = loadedDays().map { date in
                let day = calendar.startOfDay(for: date)
                let year = calendar.component(.year, from: day)
                let trackerColors = allTrackers
                    .filter { $0.hasMarker(on: day, calendar: calendar) }
                    .map(\.colorHex)
                let dayBirthdays = allBirthdays.filter {
                    $0.matches(date: day, calendar: calendar) && !$0.isAcknowledged(inYear: year)
                }

                return WeekDaySection(
                    id: day,
                    date: day,
                    isToday: calendar.isDateInToday(day),
                    events: grouped[day, default: []],
                    trackerColors: trackerColors,
                    birthdays: dayBirthdays
                )
            }

            weekTitle = CalendarDateFormatter.weekTitle(for: weekStart, calendar: calendar)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func shiftWeek(by dayOffset: Int) {
        weekStart = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) ?? weekStart
        weekTitle = CalendarDateFormatter.weekTitle(for: weekStart, calendar: calendar)

        Task {
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            await ensureLoaded(covering: weekStart, endDate: weekEnd)
        }
    }

    private func loadedDays() -> [Date] {
        var days: [Date] = []
        var current = loadedStartDate

        while current < loadedEndDateExclusive {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else {
                break
            }
            current = next
        }

        return days
    }

    private func applyOptimisticUpdate(_ updatedEvent: CalendarEvent, replacing eventID: Int64) {
        sections = sections.map { section in
            var events = section.events.filter { $0.id != eventID }
            if calendar.isDate(updatedEvent.startAt, inSameDayAs: section.date) {
                events.append(updatedEvent)
            }

            events.sort { lhs, rhs in
                if lhs.startAt == rhs.startAt {
                    if lhs.durationMinutes == rhs.durationMinutes {
                        return lhs.id < rhs.id
                    }
                    return lhs.durationMinutes < rhs.durationMinutes
                }
                return lhs.startAt < rhs.startAt
            }

            return WeekDaySection(
                id: section.id,
                date: section.date,
                isToday: section.isToday,
                events: events,
                trackerColors: section.trackerColors,
                birthdays: section.birthdays
            )
        }
    }

    private func quantizedDate(_ date: Date, stepMinutes: Int) -> Date {
        let step = max(stepMinutes, 1)
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minutes = components.minute ?? 0
        components.minute = (minutes / step) * step
        components.second = 0
        return calendar.date(from: components) ?? date
    }

    private func showBanner(_ message: String) {
        bannerDismissTask?.cancel()
        bannerMessage = message
        bannerDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.bannerMessage = nil
        }
    }
}
