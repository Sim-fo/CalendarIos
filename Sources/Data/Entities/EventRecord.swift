import Foundation
import GRDB

struct EventRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord, Sendable {
    static let databaseTableName = "events"

    var id: Int64?
    var eventTypeId: Int64?
    var customTitle: String?
    var customColorHex: Int?
    var startAtMillis: Int64
    var durationMinutes: Int
    var reminderMinutes: Int
    var note: String?
    var audioNotePath: String? = nil
    var selectedOptionId: Int64? = nil
    var selectedOptionName: String? = nil
    var lastModifiedMillis: Int64

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
