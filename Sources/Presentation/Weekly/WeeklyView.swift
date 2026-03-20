import SwiftUI

struct WeeklyView: View {
    @ObservedObject var viewModel: WeeklyViewModel
    private let calendar: Calendar

    private let hourHeight: CGFloat = 72
    private let timeColumnWidth: CGFloat = 58
    private let dayColumnWidth: CGFloat = 178

    init(viewModel: WeeklyViewModel, calendar: Calendar = .current) {
        self.viewModel = viewModel
        self.calendar = calendar
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CalendarColor.groupedBackground
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    header

                    if viewModel.isLoading && viewModel.sections.isEmpty {
                        ProgressView("Loading week...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        weeklyTimeline
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Weekly")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.openNewEvent(on: Date())
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $viewModel.isPresentingEditor) {
                EventEditorView(
                    draft: $viewModel.editorDraft,
                    eventTypes: viewModel.eventTypes,
                    isSaving: viewModel.isSaving,
                    onSave: viewModel.saveEditor,
                    onDelete: deleteAction,
                    onCancel: { viewModel.cancelEditor() }
                )
            }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button("OK") {
                    viewModel.dismissError()
                }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
            .task {
                viewModel.onAppear()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.weekTitle)
                .font(.title2.weight(.semibold))

            HStack(spacing: 10) {
                Button {
                    viewModel.showPreviousWeek()
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)

                Button("Today") {
                    viewModel.showCurrentWeek()
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewModel.showNextWeek()
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weeklyTimeline: some View {
        let timelineHeight = hourHeight * 24

        return ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: timeColumnWidth, height: 52)

                    ForEach(viewModel.sections) { section in
                        WeeklyDayHeader(
                            section: section,
                            calendar: calendar,
                            width: dayColumnWidth,
                            onAddTap: { viewModel.openNewEvent(on: section.date) }
                        )
                    }
                }
                .background(CalendarColor.cardBackground)

                ScrollView(.vertical, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 0) {
                        TimeColumnView(
                            calendar: calendar,
                            hourHeight: hourHeight,
                            width: timeColumnWidth
                        )

                        ForEach(viewModel.sections) { section in
                            WeeklyTimelineDayColumn(
                                section: section,
                                calendar: calendar,
                                width: dayColumnWidth,
                                hourHeight: hourHeight,
                                timelineHeight: timelineHeight,
                                onEventTap: viewModel.openEditor(for:)
                            )
                        }
                    }
                }
            }
            .background(CalendarColor.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.dismissError()
                }
            }
        )
    }

    private var deleteAction: (() -> Void)? {
        guard viewModel.editorDraft.id != nil else {
            return nil
        }
        return { viewModel.deleteCurrentEvent() }
    }
}

private struct WeeklyDayHeader: View {
    let section: WeekDaySection
    let calendar: Calendar
    let width: CGFloat
    let onAddTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(CalendarDateFormatter.weekdayHeader(for: section.date, calendar: calendar))
                    .font(.headline)

                Text(section.isToday ? "Today" : "\(section.events.count) events")
                    .font(.caption.weight(section.isToday ? .semibold : .regular))
                    .foregroundStyle(section.isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }

            Spacer(minLength: 0)

            Button(action: onAddTap) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(width: width, height: 52, alignment: .topLeading)
        .background(section.isToday ? Color.accentColor.opacity(0.08) : Color.clear)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
    }
}

private struct TimeColumnView: View {
    let calendar: Calendar
    let hourHeight: CGFloat
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Rectangle()
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                .frame(width: width)

            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(hourLabel(hour))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: width - 10, height: hourHeight, alignment: .topTrailing)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let components = DateComponents(calendar: calendar, hour: hour, minute: 0)
        let date = calendar.date(from: components) ?? Date()
        return CalendarDateFormatter.time(for: date, calendar: calendar)
    }
}

private struct WeeklyTimelineDayColumn: View {
    let section: WeekDaySection
    let calendar: Calendar
    let width: CGFloat
    let hourHeight: CGFloat
    let timelineHeight: CGFloat
    let onEventTap: (CalendarEvent) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            dayBackground

            ForEach(hourMarkers, id: \.self) { hour in
                Rectangle()
                    .fill(hour == currentHour ? currentHourColor : Color.primary.opacity(0.06))
                    .frame(height: hour == currentHour ? 1.5 : 1)
                    .offset(y: CGFloat(hour) * hourHeight)
            }

            if section.isToday {
                Rectangle()
                    .fill(currentTimeIndicatorColor)
                    .frame(height: 2)
                    .offset(y: currentTimeOffset)
            }

            ForEach(eventLayouts) { layout in
                WeeklyTimelineEventBlock(
                    event: layout.event,
                    calendar: calendar
                )
                .frame(width: layout.width, height: layout.height, alignment: .topLeading)
                .offset(x: layout.x, y: layout.y)
                .onTapGesture {
                    onEventTap(layout.event)
                }
            }
        }
        .frame(width: width, height: timelineHeight, alignment: .topLeading)
        .clipped()
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
    }

    private var dayBackground: some View {
        Rectangle()
            .fill(section.isToday ? Color.accentColor.opacity(0.06) : Color.clear)
    }

    private var hourMarkers: [Int] {
        Array(0...24)
    }

    private var currentHour: Int {
        calendar.component(.hour, from: Date())
    }

    private var currentHourColor: Color {
        section.isToday ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06)
    }

    private var currentTimeIndicatorColor: Color {
        Color.red.opacity(0.75)
    }

    private var currentTimeOffset: CGFloat {
        let components = calendar.dateComponents([.hour, .minute], from: Date())
        let hour = CGFloat(components.hour ?? 0)
        let minute = CGFloat(components.minute ?? 0)
        return ((hour * 60) + minute) / 60 * hourHeight
    }

    private var eventLayouts: [WeeklyTimelineEventLayout] {
        WeeklyTimelineEventLayout.make(
            events: section.events,
            calendar: calendar,
            columnWidth: width,
            hourHeight: hourHeight
        )
    }
}

private struct WeeklyTimelineEventBlock: View {
    let event: CalendarEvent
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(event.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)

            Text(timeRange)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let note = event.note, !note.isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(calendarHex: event.colorHex).opacity(0.18))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(calendarHex: event.colorHex))
                .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var timeRange: String {
        let start = CalendarDateFormatter.time(for: event.startAt, calendar: calendar)
        let end = CalendarDateFormatter.time(for: event.endAt, calendar: calendar)
        return "\(start) - \(end)"
    }
}

private struct WeeklyTimelineEventLayout: Identifiable {
    let id: Int64
    let event: CalendarEvent
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    static func make(
        events: [CalendarEvent],
        calendar: Calendar,
        columnWidth: CGFloat,
        hourHeight: CGFloat
    ) -> [WeeklyTimelineEventLayout] {
        let sorted = events.sorted { lhs, rhs in
            if lhs.startAt == rhs.startAt {
                return lhs.durationMinutes < rhs.durationMinutes
            }
            return lhs.startAt < rhs.startAt
        }

        let clusters = makeClusters(from: sorted)
        let horizontalPadding: CGFloat = 6
        let columnSpacing: CGFloat = 4

        return clusters.flatMap { cluster in
            var columnEndDates: [Date] = []
            var placements: [(event: CalendarEvent, columnIndex: Int)] = []

            for event in cluster {
                if let reusableIndex = columnEndDates.firstIndex(where: { $0 <= event.startAt }) {
                    columnEndDates[reusableIndex] = event.endAt
                    placements.append((event, reusableIndex))
                } else {
                    columnEndDates.append(event.endAt)
                    placements.append((event, columnEndDates.count - 1))
                }
            }

            let columnCount = max(columnEndDates.count, 1)
            let totalSpacing = CGFloat(columnCount - 1) * columnSpacing
            let availableWidth = columnWidth - (horizontalPadding * 2) - totalSpacing
            let eventWidth = max(32, availableWidth / CGFloat(columnCount))

            return placements.map { placement in
                let components = calendar.dateComponents([.hour, .minute], from: placement.event.startAt)
                let startHour = CGFloat(components.hour ?? 0)
                let startMinute = CGFloat(components.minute ?? 0)
                let top = ((startHour * 60) + startMinute) / 60 * hourHeight
                let rawHeight = CGFloat(placement.event.durationMinutes) / 60 * hourHeight
                let height = max(38, rawHeight)
                let x = horizontalPadding + CGFloat(placement.columnIndex) * (eventWidth + columnSpacing)

                return WeeklyTimelineEventLayout(
                    id: placement.event.id,
                    event: placement.event,
                    x: x,
                    y: top,
                    width: eventWidth,
                    height: height
                )
            }
        }
    }

    private static func makeClusters(from events: [CalendarEvent]) -> [[CalendarEvent]] {
        var clusters: [[CalendarEvent]] = []
        var currentCluster: [CalendarEvent] = []
        var currentClusterMaxEnd: Date?

        for event in events {
            guard let maxEnd = currentClusterMaxEnd else {
                currentCluster = [event]
                currentClusterMaxEnd = event.endAt
                continue
            }

            if event.startAt < maxEnd {
                currentCluster.append(event)
                currentClusterMaxEnd = max(maxEnd, event.endAt)
            } else {
                clusters.append(currentCluster)
                currentCluster = [event]
                currentClusterMaxEnd = event.endAt
            }
        }

        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }

        return clusters
    }
}

#Preview {
    let dependencies = try? CalendarDependencies.preview()
    if let dependencies {
        RootContentView(dependencies: dependencies)
    } else {
        Text("Preview unavailable")
    }
}
