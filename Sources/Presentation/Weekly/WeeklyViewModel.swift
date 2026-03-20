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
        eventBeingEditedID = nil
        editorDraft = EventDraft.empty(on: date, calendar: calendar)
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
}
