import SwiftUI

struct AppShellView: View {
    let dependencies: CalendarDependencies
    @State private var selectedCalendarMode: CalendarMode = .week
    @State private var selectedCalendarDate: Date = Date()

    var body: some View {
        CalendarHomeView(
            dependencies: dependencies,
            selectedMode: $selectedCalendarMode,
            selectedDate: $selectedCalendarDate
        )
    }
}

private struct CalendarHomeView: View {
    let dependencies: CalendarDependencies
    @Binding var selectedMode: CalendarMode
    @Binding var selectedDate: Date
    @State private var isPresentingSections = false
    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if selectedMode != .week {
                    modeReturnBar
                }

                Group {
                    switch selectedMode {
                    case .day:
                        PlaceholderFeatureView(
                            title: dayTitle,
                            subtitle: "Здесь будет дневной экран календаря с таймлайном на один день. Выбранная дата: \(longDateText(for: selectedDate)).",
                            systemImage: "calendar.day.timeline.leading",
                            showsNavigationChrome: false
                        )
                    case .week:
                        WeeklyView(
                            viewModel: WeeklyViewModel(
                                eventRepository: dependencies.eventRepository,
                                eventTypeRepository: dependencies.eventRepository
                            ),
                            showsNavigationChrome: false,
                            onWeekTitleTap: { weekStart in
                                selectedDate = weekStart
                                selectedMode = .month
                            },
                            onDayHeaderTap: { date in
                                selectedDate = date
                                selectedMode = .day
                            }
                        )
                    case .month:
                        PlaceholderFeatureView(
                            title: monthTitle,
                            subtitle: "Здесь будет месячный календарь с маркерами событий, дней рождений и трекеров. Переход выполнен к периоду, содержащему \(longDateText(for: selectedDate)).",
                            systemImage: "calendar.badge.clock",
                            showsNavigationChrome: false
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top, 8)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isPresentingSections = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
            }
            .sheet(isPresented: $isPresentingSections) {
                MoreMenuView()
            }
        }
    }

    private var navigationTitle: String {
        switch selectedMode {
        case .day:
            return "День"
        case .week:
            return "Календарь"
        case .month:
            return "Месяц"
        }
    }

    private var modeReturnBar: some View {
        HStack(spacing: 12) {
            Button {
                selectedMode = .week
            } label: {
                Label("К неделе", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)

            Spacer()

            Text(contextLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }

    private var contextLabel: String {
        switch selectedMode {
        case .day:
            return shortDateText(for: selectedDate)
        case .week:
            return ""
        case .month:
            return monthText(for: selectedDate)
        }
    }

    private var dayTitle: String {
        "День: \(shortDateText(for: selectedDate))"
    }

    private var monthTitle: String {
        "Месяц: \(monthText(for: selectedDate))"
    }

    private func shortDateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private func monthText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).capitalized
    }

    private func longDateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

private struct MoreMenuView: View {
    private let items: [PlaceholderMenuItem] = [
        .init(
            title: "Todo List",
            subtitle: "Список задач с быстрым созданием, чекбоксами и фильтрами.",
            systemImage: "checklist"
        ),
        .init(
            title: "Дни рождения",
            subtitle: "Список дней рождения, фото, напоминания и переходы в календарь.",
            systemImage: "gift"
        ),
        .init(
            title: "Трекеры",
            subtitle: "Периодические трекеры вроде замены линз, процедур и привычек.",
            systemImage: "repeat"
        ),
        .init(
            title: "Клиенты",
            subtitle: "Карточки клиентов и привязанные к ним события.",
            systemImage: "person.2"
        ),
        .init(
            title: "Шаблоны событий",
            subtitle: "Настройка типов и шаблонов событий с цветами и длительностью.",
            systemImage: "square.stack.3d.up"
        ),
        .init(
            title: "Еженедельные события",
            subtitle: "Отдельный экран для recurring weekly events и их редактирования.",
            systemImage: "calendar.badge.plus"
        ),
        .init(
            title: "Настройки",
            subtitle: "Тема, язык, формат времени, жесты и остальные параметры приложения.",
            systemImage: "gearshape"
        )
    ]

    var body: some View {
        NavigationStack {
            List(items) { item in
                NavigationLink(destination: PlaceholderFeatureView(
                    title: item.title,
                    subtitle: item.subtitle,
                    systemImage: item.systemImage
                )) {
                    HStack(spacing: 12) {
                        Image(systemName: item.systemImage)
                            .font(.title3)
                            .frame(width: 28)
                            .foregroundStyle(.tint)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Разделы")
        }
    }
}

private struct PlaceholderMenuItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
}

private enum CalendarMode: String, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }
}
