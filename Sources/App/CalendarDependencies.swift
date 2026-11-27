import Foundation

final class CalendarDependencies: @unchecked Sendable {
    let database: AppDatabase
    let eventRepository: GRDBEventRepository
    let featureRepository: GRDBFeatureRepository

    init(database: AppDatabase, calendar: Calendar = .current) {
        self.database = database
        self.eventRepository = GRDBEventRepository(dbWriter: database.dbWriter, calendar: calendar)
        self.featureRepository = GRDBFeatureRepository(dbWriter: database.dbWriter)
    }

    static func live() throws -> CalendarDependencies {
        try CalendarDependencies(database: AppDatabase.live())
    }

    static func preview() throws -> CalendarDependencies {
        let dependencies = try CalendarDependencies(database: AppDatabase.inMemory())
        try seedPreviewData(into: dependencies)
        return dependencies
    }

    private static func seedPreviewData(into dependencies: CalendarDependencies) throws {
        try dependencies.database.dbWriter.write { db in
            if try EventRecord.fetchCount(db) > 0 {
                return
            }

            let now = Date().millisecondsSince1970
            var focus = EventTypeRecord(
                id: nil,
                title: "Focus",
                defaultDurationMinutes: 90,
                colorHex: 0xFF8FBDF5,
                notifyBeforeMinutes: 10,
                lastModifiedMillis: now
            )
            var workout = EventTypeRecord(
                id: nil,
                title: "Workout",
                defaultDurationMinutes: 60,
                colorHex: 0xFF99C79B,
                notifyBeforeMinutes: 15,
                lastModifiedMillis: now
            )
            try focus.save(db)
            try workout.save(db)

            let calendar = Calendar.current
            let weekStart = calendar.startOfWeek(containing: Date())
            var records = [
                EventRecord(
                    id: nil,
                    eventTypeId: focus.id,
                    customTitle: nil,
                    customColorHex: nil,
                    startAtMillis: calendar.dateBySettingHour(9, minute: 0, on: weekStart).millisecondsSince1970,
                    durationMinutes: 90,
                    reminderMinutes: 10,
                    note: "Preview seed data",
                    lastModifiedMillis: now
                ),
                EventRecord(
                    id: nil,
                    eventTypeId: workout.id,
                    customTitle: nil,
                    customColorHex: nil,
                    startAtMillis: calendar.dateBySettingHour(
                        18,
                        minute: 30,
                        on: calendar.date(byAdding: .day, value: 2, to: weekStart) ?? weekStart
                    ).millisecondsSince1970,
                    durationMinutes: 60,
                    reminderMinutes: 15,
                    note: nil,
                    lastModifiedMillis: now
                )
            ]

            for index in records.indices {
                try records[index].save(db)
            }
        }
    }
}
