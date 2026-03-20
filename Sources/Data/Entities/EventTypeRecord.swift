import Foundation
import GRDB

struct EventTypeRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord {
    static let databaseTableName = "event_types"

    var id: Int64?
    var title: String
    var defaultDurationMinutes: Int
    var colorHex: Int
    var notifyBeforeMinutes: Int
    var lastModifiedMillis: Int64
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

