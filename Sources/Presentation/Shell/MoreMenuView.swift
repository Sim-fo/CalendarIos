import SwiftUI

struct MoreMenuView: View {
    let dependencies: CalendarDependencies
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        NavigationStack {
            List {
                Section("more.section.events") {
                    featureLink(.templates)
                    featureLink(.weeklyEvents)
                }

                Section("more.section.people_places") {
                    featureLink(.birthdays)
                    featureLink(.clients)
                    featureLink(.mapMarkers)
                }

                Section("more.section.productivity") {
                    featureLink(.todo)
                    featureLink(.trackers)
                }

                Section("more.section.app") {
                    NavigationLink {
                        TabCustomizationView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.body)
                                .frame(width: 26)
                                .foregroundStyle(.tint)

                            Text("more.customize_tabs")

                            Spacer()

                            Text("\(settings.customTabs.count)/\(AppSettingsStore.maxCustomTabs)")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        BackupView(database: dependencies.database)
                    } label: {
                        menuRow(
                            titleKey: "feature.backup.title",
                            subtitleKey: "feature.backup.subtitle",
                            systemImage: "externaldrive.badge.icloud"
                        )
                    }

                    NavigationLink {
                        SettingsView()
                    } label: {
                        menuRow(
                            titleKey: "feature.settings.title",
                            subtitleKey: "feature.settings.subtitle",
                            systemImage: "gearshape"
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("tab.more")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    @ViewBuilder
    private func featureLink(_ feature: AppFeatureTab) -> some View {
        NavigationLink {
            featureDestination(for: feature)
        } label: {
            menuRow(
                titleKey: feature.titleKey,
                subtitleKey: feature.subtitleKey,
                systemImage: feature.systemImage,
                isPinned: settings.isTabEnabled(feature)
            )
        }
    }

    @ViewBuilder
    private func featureDestination(for feature: AppFeatureTab) -> some View {
        switch feature {
        case .todo:
            TodoListView(repository: dependencies.featureRepository)
        case .trackers:
            TrackersListView(repository: dependencies.featureRepository)
        case .birthdays:
            BirthdaysListView(repository: dependencies.featureRepository)
        case .templates:
            TemplatesListView(
                repository: dependencies.eventRepository,
                optionRepository: dependencies.featureRepository
            )
        case .weeklyEvents:
            WeeklyEventsListView(dependencies: dependencies)
        case .clients:
            ClientsListView(repository: dependencies.featureRepository)
        case .mapMarkers:
            MapMarkersListView(repository: dependencies.featureRepository)
        }
    }

    @ViewBuilder
    private func menuRow(
        titleKey: LocalizedStringKey,
        subtitleKey: LocalizedStringKey,
        systemImage: String,
        isPinned: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .frame(width: 26)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                Text(subtitleKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if isPinned {
                Spacer(minLength: 4)
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
