import Foundation

protocol EventRepository: Sendable {
    func events(in interval: DateInterval) async throws -> [CalendarEvent]
    func fetchEvent(id: Int64) async throws -> CalendarEvent?
    func fetchUniqueEventTitles() async throws -> [String]
    func upsert(_ draft: EventDraft) async throws -> CalendarEvent
    func delete(id: Int64) async throws
    func seedIfNeeded(referenceDate: Date) async throws
}
