import Foundation
import SwiftUI

struct DailyFieldDetail: Identifiable, Equatable {
    let id: Int64
    let label: String?
    let value: String
}

enum DailyScheduleEntry: Identifiable, Equatable {
    case event(CalendarEvent, details: [DailyFieldDetail])
    case freeTime(start: Date, end: Date, durationMinutes: Int)

    var id: String {
        switch self {
        case .event(let event, _):
            return "event-\(event.id)-\(event.startAt.millisecondsSince1970)"
        case .freeTime(let start, let end, _):
            return "free-\(start.millisecondsSince1970)-\(end.millisecondsSince1970)"
        }
    }
}

enum DailyFreeTimeCalculator {
    static func buildSchedule(
        events: [CalendarEvent],
        detailsByEventId: [Int64: [DailyFieldDetail]] = [:],
        thresholdMinutes: Int
    ) -> [DailyScheduleEntry] {
        let sorted = events.sorted { $0.startAt < $1.startAt }
        guard !sorted.isEmpty else { return [] }

        let minGap = max(thresholdMinutes, 5)
        var entries: [DailyScheduleEntry] = []
        var latestEnd: Date?

        for event in sorted {
            if let prevEnd = latestEnd {
                let gapMinutes = Int(event.startAt.timeIntervalSince(prevEnd) / 60.0)
                if gapMinutes >= minGap {
                    entries.append(.freeTime(start: prevEnd, end: event.startAt, durationMinutes: gapMinutes))
                }
            }
            entries.append(.event(event, details: detailsByEventId[event.id, default: []]))
            if let prevEnd = latestEnd {
                latestEnd = max(prevEnd, event.endAt)
            } else {
                latestEnd = event.endAt
            }
        }
        return entries
    }
}

@MainActor
final class DailyViewModel: ObservableObject {
    @Published private(set) var trackers: [TrackerItem] = []
    @Published private(set) var birthdays: [BirthdayItem] = []
    @Published private(set) var scheduleEntries: [DailyScheduleEntry] = []
    @Published private(set) var isLoading = false

    private let eventRepository: any EventRepository
    private let featureRepository: GRDBFeatureRepository

    init(eventRepository: any EventRepository, featureRepository: GRDBFeatureRepository) {
        self.eventRepository = eventRepository
        self.featureRepository = featureRepository
    }

    func load(date: Date, calendar: Calendar, freeTimeThresholdMinutes: Int) async {
        isLoading = true
        defer { isLoading = false }

        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }

        do {
            let interval = DateInterval(start: dayStart, end: dayEnd)
            let dayEvents = try await eventRepository.events(in: interval)
            let allTrackers = try await featureRepository.fetchTrackers()
            let allBirthdays = try await featureRepository.fetchBirthdays()
            let allClients = try await featureRepository.fetchClients()
            let clientMap = Dictionary(uniqueKeysWithValues: allClients.map { ($0.id, $0) })

            trackers = allTrackers.filter { $0.hasMarker(on: dayStart, calendar: calendar) }
            birthdays = allBirthdays.filter { $0.matches(date: dayStart, calendar: calendar) }

            var detailsByEventId: [Int64: [DailyFieldDetail]] = [:]
            for event in dayEvents where !event.isRecurringInstance {
                guard let optionId = event.selectedOptionId, let typeId = event.eventTypeId else { continue }
                let options = try await featureRepository.fetchOptions(forEventTypeId: typeId)
                guard let option = options.first(where: { $0.id == optionId }) else { continue }
                let savedValues = try await featureRepository.fetchOptionValues(forEventId: event.id)
                let valueByFieldId = Dictionary(uniqueKeysWithValues: savedValues.map { ($0.fieldId, $0) })

                var details: [DailyFieldDetail] = []
                for field in option.fields {
                    switch field.fieldType {
                    case .variantText:
                        if let text = field.defaultTextValue?.nilIfBlank {
                            details.append(DailyFieldDetail(id: field.id, label: field.label, value: text))
                        }
                    case .client:
                        if let clientId = valueByFieldId[field.id]?.clientId,
                           let client = clientMap[clientId] {
                            details.append(DailyFieldDetail(id: field.id, label: field.label, value: client.name))
                        }
                    case .geoLocation:
                        if let label = valueByFieldId[field.id]?.locationLabel?.nilIfBlank {
                            details.append(DailyFieldDetail(id: field.id, label: field.label, value: label))
                        }
                    case .photo:
                        if valueByFieldId[field.id]?.photoPath != nil {
                            details.append(DailyFieldDetail(id: field.id, label: field.label, value: String(localized: "option.field.photo_attached")))
                        }
                    case .durationOverride:
                        break
                    }
                }
                if !details.isEmpty {
                    detailsByEventId[event.id] = details
                }
            }

            scheduleEntries = DailyFreeTimeCalculator.buildSchedule(
                events: dayEvents,
                detailsByEventId: detailsByEventId,
                thresholdMinutes: freeTimeThresholdMinutes
            )
        } catch {
            scheduleEntries = []
        }
    }

    func resetTracker(_ tracker: TrackerItem, on date: Date, calendar: Calendar, freeTimeThresholdMinutes: Int) async {
        try? await featureRepository.resetTracker(id: tracker.id, at: Date())
        NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
        await load(date: date, calendar: calendar, freeTimeThresholdMinutes: freeTimeThresholdMinutes)
    }
}

struct DailyView: View {
    @Binding var selectedDate: Date
    @EnvironmentObject private var settings: AppSettingsStore
    @StateObject private var viewModel: DailyViewModel

    let onBackToWeekly: () -> Void
    let onEventTap: (CalendarEvent) -> Void

    init(
        selectedDate: Binding<Date>,
        dependencies: CalendarDependencies,
        onBackToWeekly: @escaping () -> Void,
        onEventTap: @escaping (CalendarEvent) -> Void
    ) {
        _selectedDate = selectedDate
        _viewModel = StateObject(
            wrappedValue: DailyViewModel(
                eventRepository: dependencies.eventRepository,
                featureRepository: dependencies.featureRepository
            )
        )
        self.onBackToWeekly = onBackToWeekly
        self.onEventTap = onEventTap
    }

    private var calendar: Calendar {
        settings.effectiveCalendar
    }

    var body: some View {
        VStack(spacing: 0) {
            dayNavigationHeader

            if viewModel.isLoading && viewModel.scheduleEntries.isEmpty && viewModel.trackers.isEmpty && viewModel.birthdays.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.scheduleEntries.isEmpty && viewModel.trackers.isEmpty && viewModel.birthdays.isEmpty {
                ContentUnavailableView(
                    "daily.empty.title",
                    systemImage: "calendar.day.timeline.leading",
                    description: Text("daily.empty.subtitle")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.trackers) { tracker in
                            trackerCard(tracker)
                        }

                        if !viewModel.birthdays.isEmpty {
                            birthdaysCard
                        }

                        ForEach(viewModel.scheduleEntries) { entry in
                            switch entry {
                            case .event(let event, let details):
                                eventCard(event, details: details)
                            case .freeTime(let start, let end, let durationMinutes):
                                freeTimeCard(start: start, end: end, durationMinutes: durationMinutes)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .background(CalendarColor.groupedBackground)
        .gesture(
            DragGesture(minimumDistance: 36)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                    if value.translation.width < -36 {
                        shiftDay(by: 1)
                    } else if value.translation.width > 36 {
                        shiftDay(by: -1)
                    }
                }
        )
        .task(id: reloadTaskKey) {
            await viewModel.load(
                date: selectedDate,
                calendar: calendar,
                freeTimeThresholdMinutes: settings.freeTimeThresholdMinutes
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .calendarDataDidChange)) { _ in
            Task {
                await viewModel.load(
                    date: selectedDate,
                    calendar: calendar,
                    freeTimeThresholdMinutes: settings.freeTimeThresholdMinutes
                )
            }
        }
    }

    private var reloadTaskKey: String {
        "\(calendar.startOfDay(for: selectedDate).millisecondsSince1970)-\(settings.freeTimeThresholdMinutes)-\(settings.firstDayOfWeek)"
    }

    private var dayNavigationHeader: some View {
        HStack {
            Button {
                shiftDay(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onBackToWeekly) {
                VStack(spacing: 2) {
                    Text(CalendarDateFormatter.longDate(for: selectedDate, calendar: calendar))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(weekdayName(for: selectedDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                shiftDay(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func trackerCard(_ tracker: TrackerItem) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(calendarHex: tracker.colorHex))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(tracker.name)
                    .font(.subheadline.weight(.semibold))
                Text(String(format: String(localized: "trackers.interval_days"), tracker.intervalDays))
                    .font(.caption)
                    .foregroundStyle(tracker.isOverdue() ? .red : .secondary)
            }

            Spacer()

            Button("trackers.reset") {
                Task {
                    await viewModel.resetTracker(
                        tracker,
                        on: selectedDate,
                        calendar: calendar,
                        freeTimeThresholdMinutes: settings.freeTimeThresholdMinutes
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(14)
        .background(CalendarColor.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var birthdaysCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("feature.birthdays.title", systemImage: "gift.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            let currentYear = calendar.component(.year, from: selectedDate)
            ForEach(viewModel.birthdays) { birthday in
                HStack {
                    Text(birthday.name)
                        .font(.body.weight(.medium))
                    Spacer()
                    if let age = birthday.age(inYear: currentYear) {
                        Text("\(age)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CalendarColor.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func eventCard(_ event: CalendarEvent, details: [DailyFieldDetail]) -> some View {
        let startStr = CalendarDateFormatter.time(for: event.startAt, calendar: calendar, use24h: settings.use24hFormat)
        let endStr = CalendarDateFormatter.time(for: event.endAt, calendar: calendar, use24h: settings.use24hFormat)
        let durStr = DurationPickerRow.formatted(minutes: event.durationMinutes)

        return Button {
            onEventTap(event)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(calendarHex: event.colorHex))
                    .frame(width: 6)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("\(startStr) – \(endStr) · \(durStr)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if event.isRecurringInstance {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(event.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let optionName = event.selectedOptionName, !optionName.isEmpty {
                        Text(optionName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.tint)
                    }

                    ForEach(details) { detail in
                        let prefix = detail.label.map { "\($0): " } ?? ""
                        Text("\(prefix)\(detail.value)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let note = event.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .italic()
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(CalendarColor.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func freeTimeCard(start: Date, end: Date, durationMinutes: Int) -> some View {
        let startStr = CalendarDateFormatter.time(for: start, calendar: calendar, use24h: settings.use24hFormat)
        let endStr = CalendarDateFormatter.time(for: end, calendar: calendar, use24h: settings.use24hFormat)
        let durStr = DurationPickerRow.formatted(minutes: durationMinutes)

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(startStr) – \(endStr)")
                    .font(.subheadline.weight(.semibold))
                Text("\(String(localized: "daily.free_time")): \(durStr)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(Color.primary.opacity(0.25))
        )
    }

    private func shiftDay(by delta: Int) {
        if let next = calendar.date(byAdding: .day, value: delta, to: selectedDate) {
            selectedDate = next
        }
    }

    private func weekdayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date).capitalized
    }
}
