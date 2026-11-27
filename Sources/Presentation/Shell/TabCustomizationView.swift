import SwiftUI

struct TabCustomizationView: View {
    @EnvironmentObject private var settings: AppSettingsStore

    private var availableTabs: [AppFeatureTab] {
        AppFeatureTab.allCases.filter { !settings.customTabs.contains($0) }
    }

    var body: some View {
        List {
            Section {
                ForEach(settings.customTabs) { tab in
                    HStack(spacing: 12) {
                        Image(systemName: tab.systemImage)
                            .frame(width: 24)
                            .foregroundStyle(.tint)

                        Text(tab.titleKey)

                        Spacer()

                        Button {
                            withAnimation {
                                settings.toggleTab(tab)
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onMove(perform: settings.moveCustomTabs)
            } header: {
                Text(
                    String(
                        format: String(localized: "tabs_customizer.active_section"),
                        settings.customTabs.count,
                        AppSettingsStore.maxCustomTabs
                    )
                )
            } footer: {
                Text("tabs_customizer.footer")
            }

            if !availableTabs.isEmpty {
                Section("tabs_customizer.available_section") {
                    ForEach(availableTabs) { tab in
                        let canAdd = settings.customTabs.count < AppSettingsStore.maxCustomTabs
                        Button {
                            withAnimation {
                                settings.toggleTab(tab)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: tab.systemImage)
                                    .frame(width: 24)
                                    .foregroundStyle(canAdd ? Color.accentColor : Color.secondary)

                                Text(tab.titleKey)
                                    .foregroundStyle(canAdd ? .primary : .secondary)

                                Spacer()

                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(canAdd ? Color.green : Color.secondary.opacity(0.4))
                            }
                        }
                        .disabled(!canAdd)
                    }
                }
            }

            Section {
                Button("tabs_customizer.reset_default") {
                    withAnimation {
                        settings.resetCustomTabsToDefault()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("tabs_customizer.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }
}
