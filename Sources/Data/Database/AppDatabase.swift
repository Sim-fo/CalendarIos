import Foundation
import GRDB

final class AppDatabase {
    let dbWriter: DatabaseQueue

    init(path: String) throws {
        dbWriter = try DatabaseQueue(path: path)
        try DatabaseMigratorFactory.make().migrate(dbWriter)
    }

    static func live() throws -> AppDatabase {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDirectory = appSupport.appendingPathComponent("CalendarIos", isDirectory: true)
        try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        let databaseURL = appDirectory.appendingPathComponent("calendar.sqlite")
        return try AppDatabase(path: databaseURL.path)
    }

    static func inMemory() throws -> AppDatabase {
        try AppDatabase(path: ":memory:")
    }
}
