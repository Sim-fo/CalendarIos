import Foundation

@MainActor
final class WeeklyViewModel: ObservableObject {
    @Published private(set) var weekStart: Date
    @Published private(set) var weekTitle: String = ""
    @Published private(set) var sections: [WeekDaySection] = []
    @Published private(set) var eventTypes: [EventType] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?
    @Published var editorDraft: EventDraft
    @Published var isPresentingEditor = false

    private let eventRepository: any EventRepository
    private let eventTypeRepository: any EventTypeRepository
    private let calendar: Calendar
    private let initialPastDays = 21
    private let initialFutureDays = 42
    private let preloadPaddingDays = 21
    private var hasLoaded = false
    private var eventBeingEditedID: Int64?
    private var latestInlineMutationID = 0
    private var loadedStartDate: Date
    private var loadedEndDateExclusive: Date

    init(
        eventRepository: any EventRepository,
        eventTypeRepository: any EventTypeRepository,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) {
        self.eventRepository = eventRepository
        self.eventTypeRepository = eventTypeRepository
        self.calendar = calendar

        let normalizedReferenceDate = calendar.startOfDay(for: referenceDate)
        let initialWeekStart = calendar.startOfWeek(containing: normalizedReferenceDate)

        self.weekStart = initialWeekStart
        self.editorDraft = EventDraft.empty(on: normalizedReferenceDate, calendar: calendar)
        self.weekTitle = CalendarDateFormatter.weekTitle(for: initialWeekStart, calendar: calendar)
        self.loadedStartDate = calendar.date(byAdding: .day, value: -initialPastDays, to: initialWeekStart) ?? initialWeekStart
        self.loadedEndDateExclusive = calendar.date(byAdding: .day, value: initialFutureDays + 1, to: initialWeekStart) ?? initialWeekStart
    }

    func onAppear() {
        guard !hasLoaded else { return }
        hasLoaded = true

        Task {
            await loadInitialState()
        }
    }

    func showPreviousWeek() {
        shiftWeek(by: -7)
    }

    func showNextWeek() {
        shiftWeek(by: 7)
    }

    func showCurrentWeek() {
        weekStart = calendar.startOfWeek(containing: Date())
        weekTitle = CalendarDateFormatter.weekTitle(for: weekStart, calendar: calendar)
        Task {
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            await ensureLoaded(covering: weekStart, endDate: weekEnd)
        }
    }

    var initialScrollDate: Date {
        weekStart
    }

    func openNewEvent(on date: Date) {
        openNewEvent(at: calendar.dateBySettingHour(9, minute: 0, on: date))
    }

    func openNewEvent(at date: Date) {
        eventBeingEditedID = nil
        editorDraft = EventDraft.empty(on: date, calendar: calendar)
        editorDraft.startAt = quantizedDate(date, stepMinutes: 30)
        isPresentingEditor = true
    }

    func openEditor(for event: CalendarEvent) {
        eventBeingEditedID = event.id
        editorDraft = EventDraft(event: event)
        isPresentingEditor = true
    }

    func cancelEditor() {
        isPresentingEditor = false
        eventBeingEditedID = nil
    }

    func dismissError() {
        errorMessage = nil
    }

    func saveEditor() {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                editorDraft.id = eventBeingEditedID
                _ = try await eventRepository.upsert(editorDraft)
                cancelEditor()
                await reloadLoadedRange()
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
                cancelEditor()
                await reloadLoadedRange()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    func applyInlineUpdate(from original: CalendarEvent, to updated: CalendarEvent) {
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
                _ = try await eventRepository.upsert(draft)
                guard mutationID == latestInlineMutationID else { return }
                await reloadLoadedRange()
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

    private func loadInitialState() async {
        isLoading = true
        errorMessage = nil

        do {
            try await eventRepository.seedIfNeeded(referenceDate: weekStart)
            eventTypes = try await eventTypeRepository.fetchEventTypes()
            await reloadLoadedRange()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func reloadLoadedRange() async {
        do {
            eventTypes = try await eventTypeRepository.fetchEventTypes()
            let interval = DateInterval(start: loadedStartDate, end: loadedEndDateExclusive)
            let events = try await eventRepository.events(in: interval)
            let grouped = Dictionary(grouping: events) { event in
                calendar.startOfDay(for: event.startAt)
            }

            sections = loadedDays().map { date in
                let day = calendar.startOfDay(for: date)
                return WeekDaySection(
                    id: day,
                    date: day,
                    isToday: calendar.isDateInToday(day),
                    events: grouped[day, default: []]
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
                events: events
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
}
