import Foundation

protocol TodoRepository: Sendable {
    func fetchTodos() async throws -> [TodoItem]
    func upsertTodo(id: Int64?, text: String, isDone: Bool) async throws -> TodoItem
    func deleteTodo(id: Int64) async throws
}

protocol TrackerRepository: Sendable {
    func fetchTrackers() async throws -> [TrackerItem]
    func upsertTracker(
        id: Int64?,
        name: String,
        intervalDays: Int,
        createdDate: Date,
        lastResetDate: Date,
        colorHex: Int
    ) async throws -> TrackerItem
    func resetTracker(id: Int64, at date: Date) async throws
    func deleteTracker(id: Int64) async throws
    func isTrackerNameUnique(_ name: String, excludingId: Int64?) async throws -> Bool
}

protocol BirthdayRepository: Sendable {
    func fetchBirthdays() async throws -> [BirthdayItem]
    func upsertBirthday(_ item: BirthdayItem, isNew: Bool) async throws -> BirthdayItem
    func acknowledgeBirthday(id: Int64, year: Int?) async throws
    func deleteBirthday(id: Int64) async throws
}

protocol WeeklyRecurringRepository: Sendable {
    func fetchWeeklyEvents() async throws -> [WeeklyRecurringItem]
    func fetchWeeklyEvent(id: Int64) async throws -> WeeklyRecurringItem?
    func upsertWeeklyEvent(
        id: Int64?,
        templateId: Int64?,
        customTitle: String?,
        customColorHex: Int?,
        reminderMinutes: Int,
        slots: [WeeklyRecurringSlot]
    ) async throws -> WeeklyRecurringItem
    func deleteWeeklyEvent(id: Int64) async throws
}

protocol ClientRepository: Sendable {
    func fetchClients() async throws -> [ClientItem]
    func upsertClient(_ item: ClientItem, isNew: Bool) async throws -> ClientItem
    func deleteClient(id: Int64) async throws
}

protocol LocationLinkRepository: Sendable {
    func fetchLocationLinks() async throws -> [LocationLinkItem]
    func upsertLocationLink(id: Int64?, url: String, title: String?, type: String?) async throws -> LocationLinkItem
    func deleteLocationLink(id: Int64) async throws
}

protocol OptionRepository: Sendable {
    func fetchOptions(forEventTypeId eventTypeId: Int64) async throws -> [TemplateOption]
    func upsertOption(
        id: Int64?,
        eventTypeId: Int64,
        name: String,
        description: String?,
        fields: [OptionField]
    ) async throws -> TemplateOption
    func deleteOption(id: Int64) async throws
    func fetchOptionValues(forEventId eventId: Int64) async throws -> [EventOptionValue]
    func saveOptionValues(forEventId eventId: Int64, values: [EventOptionValue]) async throws
}
