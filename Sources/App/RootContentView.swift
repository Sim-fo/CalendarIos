import SwiftUI

struct RootContentView: View {
    @StateObject private var viewModel: WeeklyViewModel

    init(dependencies: CalendarDependencies) {
        _viewModel = StateObject(
            wrappedValue: WeeklyViewModel(
                eventRepository: dependencies.eventRepository,
                eventTypeRepository: dependencies.eventRepository
            )
        )
    }

    var body: some View {
        WeeklyView(viewModel: viewModel)
    }
}

