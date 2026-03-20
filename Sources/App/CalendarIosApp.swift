import SwiftUI

@main
struct CalendarIosApp: App {
    private let dependencies: CalendarDependencies

    init() {
        do {
            dependencies = try CalendarDependencies.live()
        } catch {
            fatalError("Failed to bootstrap CalendarIos dependencies: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootContentView(dependencies: dependencies)
        }
    }
}
