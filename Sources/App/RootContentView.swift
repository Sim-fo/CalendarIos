import SwiftUI

struct RootContentView: View {
    let dependencies: CalendarDependencies

    init(dependencies: CalendarDependencies) {
        self.dependencies = dependencies
    }

    var body: some View {
        AppShellView(dependencies: dependencies)
    }
}
