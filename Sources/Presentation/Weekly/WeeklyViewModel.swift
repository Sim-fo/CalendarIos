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
    private var hasLoaded = false
    private var eventBeingEditedID: Int64?

    init(
        eventRepository: any EventRepository,
        eventTypeRepository: any EventTypeRepository,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) {
        self.eventRepository = eventRepository
        self.eventTypeRepository = eventTypeRepository
        self.calendar = calendar
        self.weekStart = calendar.startOfWeek(containing: referenceDate)
        self.editorDraft = EventDraft.empty(on: referenceDate, calendar: calendar)
        self.weekTitle = CalendarDateFormatter.weekTitle(for: weekStart, calendar: calendar)
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
            await reloadWeek()
        }
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
                await reloadWeek()
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
                await reloadWeek()
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

        Task {
            do {
                var draft = EventDraft(event: original)
                draft.startAt = updated.startAt
                draft.durationMinutes = updated.durationMinutes
                _ = try await eventRepository.upsert(draft)
                await reloadWeek()
            } catch {
                errorMessage = error.localizedDescription
                await reloadWeek()
            }
        }
    }

    private func loadInitialState() async {
        isLoading = true
        errorMessage = nil

        do {
            try await eventRepository.seedIfNeeded(referenceDate: weekStart)
            eventTypes = try await eventTypeRepository.fetchEventTypes()
            await reloadWeek()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func reloadWeek() async {
        do {
            eventTypes = try await eventTypeRepository.fetchEventTypes()
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            let interval = DateInterval(start: weekStart, end: weekEnd)
            let events = try await eventRepository.events(in: interval)
            let grouped = Dictionary(grouping: events) { event in
                calendar.startOfDay(for: event.startAt)
            }
            sections = calendar.daysInWeek(containing: weekStart).map { date in
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
            await reloadWeek()
        }
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
