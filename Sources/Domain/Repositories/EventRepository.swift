import Foundation

protocol EventRepository: Sendable {
    func events(in interval: DateInterval) async throws -> [CalendarEvent]
    func upsert(_ draft: EventDraft) async throws -> CalendarEvent
    func delete(id: Int64) async throws
    func seedIfNeeded(referenceDate: Date) async throws
}

