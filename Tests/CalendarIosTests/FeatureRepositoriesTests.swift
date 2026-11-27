import Foundation
import GRDB
import XCTest
@testable import CalendarIos

final class FeatureRepositoriesTests: XCTestCase {
    func testV2MigrationCreatesAll12Tables() throws {
        let database = try AppDatabase.inMemory()
        let expectedTables = [
            "event_types",
            "events",
            "todo_items",
            "trackers",
            "birthdays",
            "weekly_recurring_events",
            "weekly_recurring_event_slots",
            "clients",
            "location_links",
            "options",
            "option_fields",
            "event_option_values"
        ]

        try database.dbWriter.read { db in
            for table in expectedTables {
                XCTAssertTrue(try db.tableExists(table), "Missing table \(table)")
            }
        }
    }

    func testTodoTrackerBirthdayClientAndLocationCRUD() async throws {
        let database = try AppDatabase.inMemory()
        let repo = GRDBFeatureRepository(dbWriter: database.dbWriter)

        // Todo
        let todo = try await repo.upsertTodo(id: nil, text: "Buy milk", isDone: false)
        XCTAssertGreaterThan(todo.id, 0)
        let toggled = try await repo.upsertTodo(id: todo.id, text: "Buy milk", isDone: true)
        XCTAssertTrue(toggled.isDone)
        let todosAfterUpsert = try await repo.fetchTodos()
        XCTAssertEqual(todosAfterUpsert.count, 1)
        try await repo.deleteTodo(id: todo.id)
        let todosAfterDelete = try await repo.fetchTodos()
        XCTAssertTrue(todosAfterDelete.isEmpty)

        // Tracker + uniqueness + reset
        let createdDate = Date(timeIntervalSince1970: 1_700_000_000)
        let tracker = try await repo.upsertTracker(
            id: nil,
            name: "Water filter",
            intervalDays: 30,
            createdDate: createdDate,
            lastResetDate: createdDate,
            colorHex: 0xFF5DADE2
        )
        let uniqueSame = try await repo.isTrackerNameUnique("water filter", excludingId: nil)
        XCTAssertFalse(uniqueSame)
        let uniqueExcludingSelf = try await repo.isTrackerNameUnique("water filter", excludingId: tracker.id)
        XCTAssertTrue(uniqueExcludingSelf)

        let newReset = Date(timeIntervalSince1970: 1_705_000_000)
        try await repo.resetTracker(id: tracker.id, at: newReset)
        let fetchedTracker = try await repo.fetchTrackers().first
        XCTAssertEqual(fetchedTracker?.lastResetDate.millisecondsSince1970, newReset.millisecondsSince1970)

        // Birthday + acknowledge
        let birthday = try await repo.upsertBirthday(
            BirthdayItem(
                id: 0,
                name: "Elena",
                birthDate: "1992-08-21",
                note: "Likes flowers",
                contactPhone: "+123456",
                contactId: nil,
                photoPath: nil,
                remindWeekBefore: true,
                remindAtStart: true,
                lastAcknowledgedYear: nil
            ),
            isNew: true
        )
        try await repo.acknowledgeBirthday(id: birthday.id, year: 2026)
        let fetchedBirthday = try await repo.fetchBirthdays().first
        XCTAssertEqual(fetchedBirthday?.lastAcknowledgedYear, 2026)

        // Client
        let client = try await repo.upsertClient(
            ClientItem(id: 0, name: "Ivan", phone: "+79990001122", email: "ivan@example.com", contactId: nil, photoPath: nil, note: "VIP"),
            isNew: true
        )
        let fetchedClients = try await repo.fetchClients()
        XCTAssertEqual(fetchedClients.first?.name, client.name)

        // Location link
        let link = try await repo.upsertLocationLink(id: nil, url: "https://maps.apple.com/?q=Studio", title: "Studio", type: "map")
        let fetchedLinks = try await repo.fetchLocationLinks()
        XCTAssertEqual(fetchedLinks.first?.displayTitle, link.displayTitle)
    }

    func testWeeklyRecurringMergesIntoEventRepositoryAndOptionsPersistValues() async throws {
        let database = try AppDatabase.inMemory()
        let featureRepo = GRDBFeatureRepository(dbWriter: database.dbWriter)
        let eventRepo = GRDBEventRepository(dbWriter: database.dbWriter)

        let template = try await eventRepo.upsertEventType(
            EventTypeDraft(id: nil, title: "Coaching", defaultDurationMinutes: 60, colorHex: 0xFFAF7AC5, notifyBeforeMinutes: 15)
        )

        // Create weekly recurring event on ISO weekday 2 (Tuesday) at 10:00
        let weekly = try await featureRepo.upsertWeeklyEvent(
            id: nil,
            templateId: template.id,
            customTitle: nil,
            customColorHex: nil,
            reminderMinutes: 15,
            slots: [
                WeeklyRecurringSlot(id: 0, weeklyEventId: 0, dayOfWeek: 2, startTime: "10:00", durationMinutes: 45, note: "Zoom", sortOrder: 0)
            ]
        )
        XCTAssertEqual(weekly.slots.count, 1)

        // Query a 7-day range starting on a Monday in local calendar
        let cal = Calendar.current
        var mondayComps = DateComponents(year: 2026, month: 6, day: 8, hour: 0, minute: 0)
        mondayComps.calendar = cal
        let monday = cal.date(from: mondayComps)!
        let nextMonday = cal.date(byAdding: .day, value: 7, to: monday)!
        let events = try await eventRepo.events(in: DateInterval(start: monday, end: nextMonday))

        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].isRecurringInstance)
        XCTAssertEqual(events[0].recurringEventId, weekly.id)
        XCTAssertEqual(events[0].title, "Coaching")
        XCTAssertEqual(events[0].durationMinutes, 45)

        // Options + OptionFields + EventOptionValues
        let option = try await featureRepo.upsertOption(
            id: nil,
            eventTypeId: template.id,
            name: "Extended",
            description: "90 min session",
            fields: [
                OptionField(id: 0, optionId: 0, fieldType: .durationOverride, sortOrder: 0, label: "Length", defaultDurationMinutes: 90, defaultTextValue: nil, defaultLocationId: nil, photoPath: nil),
                OptionField(id: 0, optionId: 0, fieldType: .variantText, sortOrder: 1, label: "Topic", defaultDurationMinutes: nil, defaultTextValue: "Strategy", defaultLocationId: nil, photoPath: nil)
            ]
        )
        XCTAssertEqual(option.fields.count, 2)

        let savedEvent = try await eventRepo.upsert(
            EventDraft(
                id: nil,
                eventTypeId: template.id,
                customTitle: "",
                customColorHex: nil,
                startAt: monday,
                durationMinutes: 90,
                reminderMinutes: 15,
                note: "Prep notes",
                selectedOptionId: option.id,
                selectedOptionName: option.name
            )
        )
        let textFieldId = option.fields[1].id
        try await featureRepo.saveOptionValues(
            forEventId: savedEvent.id,
            values: [
                EventOptionValue(id: 0, eventId: savedEvent.id, fieldId: textFieldId, textValue: "Q3 Roadmap", photoPath: nil, clientId: nil, latitude: nil, longitude: nil, locationLabel: nil)
            ]
        )
        let loadedValues = try await featureRepo.fetchOptionValues(forEventId: savedEvent.id)
        XCTAssertEqual(loadedValues.count, 1)
        XCTAssertEqual(loadedValues.first?.textValue, "Q3 Roadmap")
    }
}
