import SwiftUI

struct DayPieSegment: Equatable {
    let colorHex: Int
    let fraction: Double
}

struct DayPieChartView: View {
    let segments: [DayPieSegment]

    var body: some View {
        Canvas { context, size in
            guard !segments.isEmpty else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 2
            var startAngle = Angle.degrees(-90)

            for segment in segments {
                let sweep = Angle.degrees(max(segment.fraction * 360.0, 2.0))
                let endAngle = startAngle + sweep
                var path = Path()
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false
                )
                context.stroke(
                    path,
                    with: .color(Color(calendarHex: segment.colorHex)),
                    style: StrokeStyle(lineWidth: 3.0, lineCap: .butt)
                )
                startAngle = endAngle
            }
        }
    }
}

struct MonthIdentifier: Identifiable, Hashable {
    let year: Int
    let month: Int

    var id: String { "\(year)-\(month)" }

    func startDate(calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }
}

@MainActor
final class MonthlyViewModel: ObservableObject {
    @Published private(set) var eventsByDay: [Date: [CalendarEvent]] = [:]
    @Published private(set) var trackers: [TrackerItem] = []
    @Published private(set) var birthdays: [BirthdayItem] = []

    private let eventRepository: any EventRepository
    private let featureRepository: GRDBFeatureRepository
    private var loadedMonths = Set<MonthIdentifier>()

    init(eventRepository: any EventRepository, featureRepository: GRDBFeatureRepository) {
        self.eventRepository = eventRepository
        self.featureRepository = featureRepository
    }

    func reloadAll(around centerMonth: MonthIdentifier, calendar: Calendar) async {
        loadedMonths.removeAll()
        eventsByDay.removeAll()
        do {
            trackers = try await featureRepository.fetchTrackers()
            birthdays = try await featureRepository.fetchBirthdays()
        } catch {
            trackers = []
            birthdays = []
        }
        await ensureLoaded(month: centerMonth, calendar: calendar)
    }

    func ensureLoaded(month: MonthIdentifier, calendar: Calendar) async {
        guard !loadedMonths.contains(month) else { return }
        loadedMonths.insert(month)

        let start = month.startDate(calendar: calendar)
        guard let end = calendar.date(byAdding: .month, value: 1, to: start) else { return }

        do {
            let events = try await eventRepository.events(in: DateInterval(start: start, end: end))
            let grouped = Dictionary(grouping: events) { calendar.startOfDay(for: $0.startAt) }
            for (day, list) in grouped {
                eventsByDay[day] = list
            }
        } catch {
            // Keep existing cached months
        }
    }
}

struct MonthlyView: View {
    let targetDate: Date
    let onSelectDay: (Date) -> Void
    let onSelectYear: (Int) -> Void

    @EnvironmentObject private var settings: AppSettingsStore
    @StateObject private var viewModel: MonthlyViewModel
    @State private var didScrollInitial = false

    init(
        targetDate: Date,
        dependencies: CalendarDependencies,
        onSelectDay: @escaping (Date) -> Void,
        onSelectYear: @escaping (Int) -> Void
    ) {
        self.targetDate = targetDate
        _viewModel = StateObject(
            wrappedValue: MonthlyViewModel(
                eventRepository: dependencies.eventRepository,
                featureRepository: dependencies.featureRepository
            )
        )
        self.onSelectDay = onSelectDay
        self.onSelectYear = onSelectYear
    }

    private var calendar: Calendar {
        settings.effectiveCalendar
    }

    private var targetMonth: MonthIdentifier {
        let comps = calendar.dateComponents([.year, .month], from: targetDate)
        return MonthIdentifier(year: comps.year ?? 2026, month: comps.month ?? 1)
    }

    private var months: [MonthIdentifier] {
        let anchor = targetMonth.startDate(calendar: calendar)
        return (-18...18).compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: offset, to: anchor) else { return nil }
            let comps = calendar.dateComponents([.year, .month], from: date)
            return MonthIdentifier(year: comps.year ?? 2026, month: comps.month ?? 1)
        }
    }

    private var orderedWeekdayLabels: [(label: String, isWeekend: Bool)] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let startIdx = max(0, min(calendar.firstWeekday - 1, 6))
        return (0..<7).map { offset in
            let idx = (startIdx + offset) % 7
            let isWeekend = (idx == 0 || idx == 6)
            return (String(symbols[idx].prefix(2)).capitalized, isWeekend)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(months) { month in
                        monthSection(month)
                            .id(month.id)
                            .task {
                                await viewModel.ensureLoaded(month: month, calendar: calendar)
                            }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemBackground))
            .onAppear {
                if !didScrollInitial {
                    didScrollInitial = true
                    proxy.scrollTo(targetMonth.id, anchor: .top)
                }
            }
            .onChange(of: targetMonth) { _, newMonth in
                proxy.scrollTo(newMonth.id, anchor: .top)
            }
        }
        .task {
            await viewModel.reloadAll(around: targetMonth, calendar: calendar)
        }
        .onReceive(NotificationCenter.default.publisher(for: .calendarDataDidChange)) { _ in
            Task {
                await viewModel.reloadAll(around: targetMonth, calendar: calendar)
            }
        }
    }

    private func monthSection(_ month: MonthIdentifier) -> some View {
        let startDate = month.startDate(calendar: calendar)
        let daysInMonth = calendar.range(of: .day, in: .month, for: startDate)?.count ?? 30
        let firstWeekdayOfMonth = calendar.component(.weekday, from: startDate)
        let leadingEmpty = (firstWeekdayOfMonth - calendar.firstWeekday + 7) % 7
        let totalCells = ((leadingEmpty + daysInMonth + 6) / 7) * 7
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

        return VStack(spacing: 8) {
            Button {
                onSelectYear(month.year)
            } label: {
                Text(CalendarDateFormatter.monthYear(for: startDate, calendar: calendar))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            HStack(spacing: 2) {
                ForEach(Array(orderedWeekdayLabels.enumerated()), id: \.offset) { _, item in
                    Text(item.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(item.isWeekend ? Color.red.opacity(0.8) : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<totalCells, id: \.self) { cellIndex in
                    let dayNumber = cellIndex - leadingEmpty + 1
                    if dayNumber >= 1 && dayNumber <= daysInMonth,
                       let date = calendar.date(byAdding: .day, value: dayNumber - 1, to: startDate) {
                        dayCell(date: date, dayNumber: dayNumber, year: month.year, month: month.month)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
    }

    private func dayCell(date: Date, dayNumber: Int, year: Int, month: Int) -> some View {
        let normalizedDay = calendar.startOfDay(for: date)
        let isToday = calendar.isDateInToday(normalizedDay)
        let dayEvents = viewModel.eventsByDay[normalizedDay, default: []]
        let totalMinutes = dayEvents.reduce(0) { $0 + max($1.durationMinutes, 1) }
        let segments: [DayPieSegment] = totalMinutes > 0
            ? dayEvents.map { DayPieSegment(colorHex: $0.colorHex, fraction: Double(max($0.durationMinutes, 1)) / Double(totalMinutes)) }
            : []

        let trackerColors = viewModel.trackers
            .filter { $0.markerDays(inYear: year, month: month, calendar: calendar).contains(dayNumber) }
            .map(\.colorHex)

        let birthdayCount = viewModel.birthdays.filter {
            $0.matches(date: normalizedDay, calendar: calendar) && !$0.isAcknowledged(inYear: year)
        }.count

        return Button {
            onSelectDay(normalizedDay)
        } label: {
            HStack(spacing: 2) {
                VStack(spacing: 2) {
                    ForEach(Array(trackerColors.prefix(3).enumerated()), id: \.offset) { _, hex in
                        Circle()
                            .fill(Color(calendarHex: hex))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(width: 6)

                ZStack {
                    if !segments.isEmpty {
                        DayPieChartView(segments: segments)
                            .frame(width: 34, height: 34)
                    }

                    if isToday {
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 26, height: 26)
                    }

                    Text("\(dayNumber)")
                        .font(.subheadline.weight(isToday || birthdayCount > 0 ? .bold : .medium))
                        .foregroundStyle(
                            isToday
                                ? Color(uiColor: .systemBackground)
                                : (birthdayCount > 0 ? Color.accentColor : Color.primary)
                        )
                }
                .frame(width: 34, height: 34)

                VStack(spacing: 2) {
                    ForEach(0..<min(birthdayCount, 3), id: \.self) { _ in
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(width: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
