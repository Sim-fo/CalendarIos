import Foundation
import GRDB

struct EventRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord {
    static let databaseTableName = "events"

    var id: Int64?
    var eventTypeId: Int64?
    var customTitle: String?
    var customColorHex: Int?
    var startAtMillis: Int64
    var durationMinutes: Int
    var reminderMinutes: Int
    var note: String?
    var lastModifiedMillis: Int64
}

