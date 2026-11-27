import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore

    private static let freeTimePresets: [Int] = [15, 30, 60, 120, 180]
    @State private var isCustomFreeTimePresented = false
    @State private var customFreeTimeInput = ""

    private var appVersionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section("settings.section.general") {
                Picker("settings.theme", selection: $settings.themeMode) {
                    Text("settings.theme.system").tag(AppThemeMode.system)
                    Text("settings.theme.dark").tag(AppThemeMode.dark)
                    Text("settings.theme.light").tag(AppThemeMode.light)
                }

                Picker("settings.time_format", selection: $settings.use24hFormat) {
                    Text("settings.time_format.24h").tag(true)
                    Text("settings.time_format.12h").tag(false)
                }

                Picker("settings.first_day_of_week", selection: $settings.firstDayOfWeek) {
                    Text("settings.weekday.monday").tag(2)
                    Text("settings.weekday.sunday").tag(1)
                }

                Picker("settings.free_time_threshold", selection: freeTimeBinding) {
                    ForEach(Self.freeTimePresets, id: \.self) { minutes in
                        Text(DurationPickerRow.formatted(minutes: minutes)).tag(minutes)
                    }
                    Text(customFreeTimeLabel).tag(-1)
                }
            }

            Section("settings.section.calendar_and_navigation") {
                NavigationLink {
                    WeekViewSettingsView()
                } label: {
                    Label("settings.week_view_settings", systemImage: "calendar")
                }

                NavigationLink {
                    TabCustomizationView()
                } label: {
                    HStack {
                        Label("more.customize_tabs", systemImage: "slider.horizontal.3")
                        Spacer()
                        Text("\(settings.customTabs.count)/\(AppSettingsStore.maxCustomTabs)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("settings.section.about") {
                HStack {
                    Text("settings.version")
                    Spacer()
                    Text(appVersionLabel)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .navigationTitle("feature.settings.title")
        .navigationBarTitleDisplayMode(.inline)
        .alert("settings.free_time_custom_title", isPresented: $isCustomFreeTimePresented) {
            TextField("settings.free_time_minutes_placeholder", text: $customFreeTimeInput)
                .keyboardType(.numberPad)
            Button("common.ok") {
                if let minutes = Int(customFreeTimeInput.trimmingCharacters(in: .whitespaces)), minutes >= 5 {
                    settings.freeTimeThresholdMinutes = minutes
                }
            }
            Button("common.cancel", role: .cancel) {}
        }
    }

    private var freeTimeBinding: Binding<Int> {
        Binding(
            get: {
                Self.freeTimePresets.contains(settings.freeTimeThresholdMinutes)
                    ? settings.freeTimeThresholdMinutes
                    : -1
            },
            set: { newValue in
                if newValue == -1 {
                    customFreeTimeInput = String(settings.freeTimeThresholdMinutes)
                    isCustomFreeTimePresented = true
                } else {
                    settings.freeTimeThresholdMinutes = newValue
                }
            }
        )
    }

    private var customFreeTimeLabel: String {
        if !Self.freeTimePresets.contains(settings.freeTimeThresholdMinutes) {
            return "\(String(localized: "duration.custom")) (\(DurationPickerRow.formatted(minutes: settings.freeTimeThresholdMinutes)))"
        }
        return String(localized: "duration.custom")
    }
}
