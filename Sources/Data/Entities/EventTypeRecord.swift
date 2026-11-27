import Foundation
import GRDB

struct EventTypeRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "event_types"

    var id: Int64?
    var title: String
    var defaultDurationMinutes: Int
    var colorHex: Int
    var notifyBeforeMinutes: Int
    var lastModifiedMillis: Int64

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension EventTypeRecord {
    func asDomain() -> EventType? {
        guard let id else { return nil }
        return EventType(
            id: id,
            title: title,
            defaultDurationMinutes: defaultDurationMinutes,
            colorHex: colorHex,
            notifyBeforeMinutes: notifyBeforeMinutes
        )
    }
}
