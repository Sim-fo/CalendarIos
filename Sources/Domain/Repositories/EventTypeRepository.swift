import Foundation

protocol EventTypeRepository: Sendable {
    func fetchEventTypes() async throws -> [EventType]
    func fetchEventTypesWithCounts() async throws -> [EventTypeWithCount]
    func fetchEventType(id: Int64) async throws -> EventType?
    func upsertEventType(_ draft: EventTypeDraft) async throws -> EventType
    func deleteEventType(id: Int64, deleteLinkedEvents: Bool) async throws
    func isEventTypeTitleUnique(_ title: String, excludingId: Int64?) async throws -> Bool
}
