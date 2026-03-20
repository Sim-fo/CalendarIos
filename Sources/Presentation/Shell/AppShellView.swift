import SwiftUI

struct AppShellView: View {
    let dependencies: CalendarDependencies

    var body: some View {
        TabView {
            WeeklyView(
                viewModel: WeeklyViewModel(
                    eventRepository: dependencies.eventRepository,
                    eventTypeRepository: dependencies.eventRepository
                )
            )
            .tabItem {
                Label("Неделя", systemImage: "calendar")
            }

            PlaceholderFeatureView(
                title: "Дневной вид",
                subtitle: "Здесь будет дневной экран календаря с таймлайном на один день.",
                systemImage: "calendar.day.timeline.leading"
            )
            .tabItem {
                Label("День", systemImage: "calendar.day.timeline.leading")
            }

            PlaceholderFeatureView(
                title: "Месячный вид",
                subtitle: "Здесь будет месячный календарь с маркерами событий, дней рождений и трекеров.",
                systemImage: "calendar.badge.clock"
            )
            .tabItem {
                Label("Месяц", systemImage: "calendar.badge.clock")
            }

            MoreMenuView()
                .tabItem {
                    Label("Ещё", systemImage: "square.grid.2x2")
                }
        }
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

