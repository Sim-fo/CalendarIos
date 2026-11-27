import SwiftUI

@MainActor
final class YearlyViewModel: ObservableObject {
    @Published private(set) var dominantColorByDay: [Date: Int] = [:]
    @Published private(set) var birthdayDaysByMonth: [Int: Set<Int>] = [:]

    private let eventRepository: any EventRepository
    private let featureRepository: GRDBFeatureRepository

    init(eventRepository: any EventRepository, featureRepository: GRDBFeatureRepository) {
        self.eventRepository = eventRepository
        self.featureRepository = featureRepository
    }

    func load(year: Int, calendar: Calendar) async {
        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let yearEnd = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
            return
        }

        do {
            let events = try await eventRepository.events(in: DateInterval(start: yearStart, end: yearEnd))
            let grouped = Dictionary(grouping: events) { calendar.startOfDay(for: $0.startAt) }

            var colorMap: [Date: Int] = [:]
            for (day, dayEvents) in grouped {
                var counts: [Int: Int] = [:]
                for event in dayEvents {
                    counts[event.colorHex, default: 0] += 1
                }
                if let dominant = counts.max(by: { $0.value < $1.value })?.key {
                    colorMap[day] = dominant
                }
            }
            dominantColorByDay = colorMap

            let birthdays = try await featureRepository.fetchBirthdays()
            var bMap: [Int: Set<Int>] = [:]
            for birthday in birthdays {
                if let date = birthday.dateInYear(year, calendar: calendar) {
                    let comps = calendar.dateComponents([.month, .day], from: date)
                    if let m = comps.month, let d = comps.day {
                        bMap[m, default: []].insert(d)
                    }
                }
            }
            birthdayDaysByMonth = bMap
        } catch {
            dominantColorByDay = [:]
            birthdayDaysByMonth = [:]
        }
    }
}

struct YearlyView: View {
    @Binding var selectedYear: Int
    let onSelectMonth: (Date) -> Void

    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @StateObject private var viewModel: YearlyViewModel

    init(
        selectedYear: Binding<Int>,
        dependencies: CalendarDependencies,
        onSelectMonth: @escaping (Date) -> Void
    ) {
        _selectedYear = selectedYear
        _viewModel = StateObject(
            wrappedValue: YearlyViewModel(
                eventRepository: dependencies.eventRepository,
                featureRepository: dependencies.featureRepository
            )
        )
        self.onSelectMonth = onSelectMonth
    }

    private var calendar: Calendar {
        settings.effectiveCalendar
    }

    private var gridColumns: [GridItem] {
        let count = sizeClass == .regular ? 4 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    private var orderedWeekdayInitials: [(label: String, isWeekend: Bool)] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let startIdx = max(0, min(calendar.firstWeekday - 1, 6))
        return (0..<7).map { offset in
            let idx = (startIdx + offset) % 7
            return (symbols[idx], idx == 0 || idx == 6)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    selectedYear -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Text(String(selectedYear))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()

                Spacer()

                Button {
                    selectedYear += 1
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

            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 10) {
                    ForEach(1...12, id: \.self) { month in
                        miniMonthCard(month: month)
                    }
                }
                .padding(12)
            }
        }
        .background(CalendarColor.groupedBackground)
        .task(id: "\(selectedYear)-\(settings.firstDayOfWeek)") {
            await viewModel.load(year: selectedYear, calendar: calendar)
        }
        .onReceive(NotificationCenter.default.publisher(for: .calendarDataDidChange)) { _ in
            Task {
                await viewModel.load(year: selectedYear, calendar: calendar)
            }
        }
    }

    private func miniMonthCard(month: Int) -> some View {
        let monthStart = calendar.date(from: DateComponents(year: selectedYear, month: month, day: 1)) ?? Date()
        let daysCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingEmpty = (firstWeekday - calendar.firstWeekday + 7) % 7
        let totalCells = ((leadingEmpty + daysCount + 6) / 7) * 7
        let birthdayDays = viewModel.birthdayDaysByMonth[month, default: []]

        let monthNameFormatter = DateFormatter()
        monthNameFormatter.calendar = calendar
        monthNameFormatter.locale = calendar.locale ?? .current
        monthNameFormatter.dateFormat = "LLLL"
        let monthTitle = monthNameFormatter.string(from: monthStart).capitalized

        let isCurrentMonth = calendar.component(.year, from: Date()) == selectedYear
            && calendar.component(.month, from: Date()) == month

        return Button {
            onSelectMonth(monthStart)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(monthTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isCurrentMonth ? Color.accentColor : Color.primary)
                    .lineLimit(1)

                HStack(spacing: 0) {
                    ForEach(Array(orderedWeekdayInitials.enumerated()), id: \.offset) { _, item in
                        Text(item.label)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(item.isWeekend ? Color.red.opacity(0.75) : .secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                let dayColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
                LazyVGrid(columns: dayColumns, spacing: 2) {
                    ForEach(0..<totalCells, id: \.self) { idx in
                        let dayNum = idx - leadingEmpty + 1
                        if dayNum >= 1 && dayNum <= daysCount,
                           let date = calendar.date(byAdding: .day, value: dayNum - 1, to: monthStart) {
                            let normalized = calendar.startOfDay(for: date)
                            let isToday = calendar.isDateInToday(normalized)
                            let eventColorHex = viewModel.dominantColorByDay[normalized]
                            let hasBirthday = birthdayDays.contains(dayNum)

                            VStack(spacing: 1) {
                                ZStack {
                                    if isToday {
                                        Circle()
                                            .fill(Color.primary)
                                            .frame(width: 14, height: 14)
                                    }
                                    Text("\(dayNum)")
                                        .font(.system(size: 8, weight: isToday || eventColorHex != nil ? .bold : .regular))
                                        .foregroundStyle(
                                            isToday
                                                ? Color(uiColor: .systemBackground)
                                                : (eventColorHex.map { Color(calendarHex: $0) } ?? Color.primary)
                                        )
                                }
                                .frame(height: 14)

                                Circle()
                                    .fill(hasBirthday ? Color.orange : Color.clear)
                                    .frame(width: 3, height: 3)
                            }
                        } else {
                            Color.clear.frame(height: 18)
                        }
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(CalendarColor.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isCurrentMonth ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
