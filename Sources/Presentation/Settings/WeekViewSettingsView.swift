import SwiftUI

struct WeekViewSettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        Form {
            Section("settings.section.general") {
                Picker("week_settings.visible_days", selection: $settings.visibleDays) {
                    ForEach(1...10, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }

                Picker("week_settings.scroll_step", selection: $settings.scrollStepDays) {
                    ForEach(1...settings.visibleDays, id: \.self) { step in
                        Text("\(step)").tag(step)
                    }
                }

                Toggle("week_settings.start_from_today", isOn: $settings.showWeekFromCurrentDay)
                Toggle("week_settings.haptic_feedback", isOn: $settings.allowHapticFeedback)
            }

            Section("week_settings.section.snapping_and_display") {
                Picker("week_settings.quantization_step", selection: $settings.quantizationMinutes) {
                    ForEach(AppSettingsStore.allowedQuantizationSteps, id: \.self) { minutes in
                        Text(DurationPickerRow.formatted(minutes: minutes)).tag(minutes)
                    }
                }
            }

            Section("week_settings.guide_highlight") {
                ColorSwatchPickerView(
                    selectedColorHex: $settings.guideHighlightColorHex,
                    useExtendedPresets: false
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("week_settings.opacity")
                        Spacer()
                        Text("\(settings.guideHighlightAlphaPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { Double(settings.guideHighlightAlphaPercent) },
                            set: { settings.guideHighlightAlphaPercent = Int($0.rounded()) }
                        ),
                        in: 0...25,
                        step: 1
                    )
                }
            }

            Section("week_settings.today_highlight") {
                ColorSwatchPickerView(
                    selectedColorHex: $settings.todayHighlightColorHex,
                    useExtendedPresets: false
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("week_settings.opacity")
                        Spacer()
                        Text("\(settings.todayHighlightAlphaPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { Double(settings.todayHighlightAlphaPercent) },
                            set: { settings.todayHighlightAlphaPercent = Int($0.rounded()) }
                        ),
                        in: 0...25,
                        step: 1
                    )
                }
            }
        }
        .navigationTitle("settings.week_view_settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
