import SwiftUI

struct RootContentView: View {
    let dependencies: CalendarDependencies
    @StateObject private var settingsStore: AppSettingsStore

    init(
        dependencies: CalendarDependencies,
        settingsStore: AppSettingsStore = AppSettingsStore()
    ) {
        self.dependencies = dependencies
        _settingsStore = StateObject(wrappedValue: settingsStore)
    }

    var body: some View {
        AppShellView(dependencies: dependencies)
            .environmentObject(settingsStore)
            .preferredColorScheme(settingsStore.themeMode.colorScheme)
    }
}
