import SwiftUI

@main
struct CalendarIosApp: App {
    private let dependencies: CalendarDependencies?

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static var isRunningUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITesting")
    }

    init() {
        if Self.isRunningUnitTests && !Self.isRunningUITests {
            dependencies = nil
            return
        }

        do {
            dependencies = Self.isRunningUITests
                ? try CalendarDependencies.preview()
                : try CalendarDependencies.live()
        } catch {
            fatalError("Failed to bootstrap CalendarIos dependencies: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if let dependencies {
                RootContentView(dependencies: dependencies)
            } else {
                Color.clear
            }
        }
    }
}
