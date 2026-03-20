import Foundation

struct EventType: Identifiable, Equatable, Sendable {
    let id: Int64
    let title: String
    let defaultDurationMinutes: Int
    let colorHex: Int
    let notifyBeforeMinutes: Int
}

