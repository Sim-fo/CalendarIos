import XCTest
@testable import CalendarIos

@MainActor
final class AppSettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.simfogames.calendar.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultCustomTabsAndPersistence() {
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.customTabs, [.todo, .trackers])

        XCTAssertTrue(store.toggleTab(.birthdays))
        XCTAssertEqual(store.customTabs, [.todo, .trackers, .birthdays])

        // Max 3 custom tabs enforced
        XCTAssertFalse(store.toggleTab(.clients))
        XCTAssertEqual(store.customTabs.count, 3)

        // Removing frees up a slot
        XCTAssertTrue(store.toggleTab(.todo))
        XCTAssertEqual(store.customTabs, [.trackers, .birthdays])

        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.customTabs, [.trackers, .birthdays])
    }

    func testClampingSettingsValues() {
        let store = AppSettingsStore(defaults: defaults)
        store.visibleDays = 20
        XCTAssertEqual(store.visibleDays, 10)

        store.scrollStepDays = 10
        store.visibleDays = 4
        XCTAssertEqual(store.scrollStepDays, 4)

        store.quantizationMinutes = 17
        XCTAssertEqual(store.quantizationMinutes, 30)

        store.quantizationMinutes = 15
        XCTAssertEqual(store.quantizationMinutes, 15)
    }
}
