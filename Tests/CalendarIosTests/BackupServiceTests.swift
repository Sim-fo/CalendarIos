import Foundation
import XCTest
@testable import CalendarIos

final class BackupServiceTests: XCTestCase {
    func testFullRoundTripExportAndImportAcrossAllTables() async throws {
        let sourceDB = try AppDatabase.inMemory()
        let eventRepo = GRDBEventRepository(dbWriter: sourceDB.dbWriter)
        let featureRepo = GRDBFeatureRepository(dbWriter: sourceDB.dbWriter)
        let sourceBackup = BackupService(dbWriter: sourceDB.dbWriter)

        // Populate every entity family
        let template = try await eventRepo.upsertEventType(
            EventTypeDraft(id: nil, title: "Therapy", defaultDurationMinutes: 50, colorHex: 0xFF48C9B0, notifyBeforeMinutes: 10)
        )
        let client = try await featureRepo.upsertClient(
            ClientItem(id: 0, name: "Maria", phone: "+15551234", email: "m@example.com", contactId: nil, photoPath: nil, note: nil),
            isNew: true
        )
        let location = try await featureRepo.upsertLocationLink(id: nil, url: "https://maps.apple.com/?q=Office", title: "Office", type: "map")
        let option = try await featureRepo.upsertOption(
            id: nil,
            eventTypeId: template.id,
            name: "In-person",
            description: nil,
            fields: [
                OptionField(id: 0, optionId: 0, fieldType: .client, sortOrder: 0, label: "Client", defaultDurationMinutes: nil, defaultTextValue: nil, defaultLocationId: nil, photoPath: nil),
                OptionField(id: 0, optionId: 0, fieldType: .geoLocation, sortOrder: 1, label: "Place", defaultDurationMinutes: nil, defaultTextValue: nil, defaultLocationId: location.id, photoPath: nil)
            ]
        )
        let event = try await eventRepo.upsert(
            EventDraft(
                id: nil,
                eventTypeId: template.id,
                customTitle: "",
                customColorHex: nil,
                startAt: Date(timeIntervalSince1970: 1_750_000_000),
                durationMinutes: 50,
                reminderMinutes: 10,
                note: "Session 1",
                audioNotePath: "audio_1.m4a",
                selectedOptionId: option.id,
                selectedOptionName: option.name
            )
        )
        try await featureRepo.saveOptionValues(
            forEventId: event.id,
            values: [
                EventOptionValue(id: 0, eventId: event.id, fieldId: option.fields[0].id, textValue: nil, photoPath: nil, clientId: client.id, latitude: nil, longitude: nil, locationLabel: nil)
            ]
        )
        _ = try await featureRepo.upsertTodo(id: nil, text: "Send invoice", isDone: false)
        _ = try await featureRepo.upsertTracker(
            id: nil, name: "Vitamins", intervalDays: 7,
            createdDate: Date(timeIntervalSince1970: 1_749_000_000),
            lastResetDate: Date(timeIntervalSince1970: 1_749_500_000),
            colorHex: 0xFFF5B041
        )
        _ = try await featureRepo.upsertBirthday(
            BirthdayItem(id: 0, name: "Mom", birthDate: "1968-04-12", note: nil, contactPhone: nil, contactId: nil, photoPath: nil, remindWeekBefore: true, remindAtStart: true, lastAcknowledgedYear: nil),
            isNew: true
        )
        _ = try await featureRepo.upsertWeeklyEvent(
            id: nil,
            templateId: template.id,
            customTitle: nil,
            customColorHex: nil,
            reminderMinutes: 10,
            slots: [
                WeeklyRecurringSlot(id: 0, weeklyEventId: 0, dayOfWeek: 4, startTime: "14:00", durationMinutes: 50, note: nil, sortOrder: 0)
            ]
        )

        let sourceSummary = try await sourceBackup.fetchSummary()
        XCTAssertEqual(sourceSummary.eventCount, 1)
        XCTAssertEqual(sourceSummary.templateCount, 1)
        XCTAssertEqual(sourceSummary.todoCount, 1)
        XCTAssertEqual(sourceSummary.trackerCount, 1)
        XCTAssertEqual(sourceSummary.birthdayCount, 1)
        XCTAssertEqual(sourceSummary.weeklyRecurringCount, 1)
        XCTAssertEqual(sourceSummary.clientCount, 1)
        XCTAssertEqual(sourceSummary.locationCount, 1)

        // Export JSON
        let jsonData = try await sourceBackup.exportJSONData()
        XCTAssertFalse(jsonData.isEmpty)

        // Import into a brand-new empty DB
        let targetDB = try AppDatabase.inMemory()
        let targetBackup = BackupService(dbWriter: targetDB.dbWriter)
        let targetFeatureRepo = GRDBFeatureRepository(dbWriter: targetDB.dbWriter)

        try await targetBackup.importJSONData(jsonData)

        let targetSummary = try await targetBackup.fetchSummary()
        XCTAssertEqual(targetSummary, sourceSummary)

        let restoredOptions = try await targetFeatureRepo.fetchOptions(forEventTypeId: template.id)
        XCTAssertEqual(restoredOptions.count, 1)
        XCTAssertEqual(restoredOptions.first?.fields.count, 2)

        let restoredValues = try await targetFeatureRepo.fetchOptionValues(forEventId: event.id)
        XCTAssertEqual(restoredValues.count, 1)
        XCTAssertEqual(restoredValues.first?.clientId, client.id)
    }
}
