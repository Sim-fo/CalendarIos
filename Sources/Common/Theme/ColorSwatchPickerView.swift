import SwiftUI

struct ColorSwatchPickerView: View {
    @Binding var selectedColorHex: Int
    var useExtendedPresets: Bool = true

    private var presets: [Int] {
        useExtendedPresets ? CalendarColor.pastelPresets : CalendarColor.compactPresets
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(calendarHex: CalendarColor.opaqueHex(selectedColorHex)) },
            set: { newColor in
                selectedColorHex = CalendarColor.hex(from: newColor)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(presets, id: \.self) { hex in
                    let isSelected = (hex & 0x00FFFFFF) == (selectedColorHex & 0x00FFFFFF)
                    Button {
                        selectedColorHex = CalendarColor.opaqueHex(hex)
                    } label: {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(calendarHex: hex))
                            .frame(height: 36)
                            .overlay {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.primary, lineWidth: 2.5)
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.black.opacity(0.75))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            ColorPicker("color.custom_picker", selection: colorBinding, supportsOpacity: false)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

struct DurationPickerRow: View {
    @Binding var durationMinutes: Int

    private static let presets: [Int] = [15, 30, 45, 60, 90, 120, 180, 1440]

    @State private var isCustomExpanded = false
    @State private var customHoursText = ""

    private var isPreset: Bool {
        Self.presets.contains(durationMinutes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("duration.label", selection: presetSelectionBinding) {
                ForEach(Self.presets, id: \.self) { minutes in
                    Text(Self.formatted(minutes: minutes)).tag(minutes)
                }
                Text(customOptionLabel).tag(-1)
            }

            if isCustomExpanded || !isPreset {
                HStack(spacing: 12) {
                    TextField("duration.custom_hours_placeholder", text: $customHoursText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)

                    Button("common.ok") {
                        applyManualHours()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(parsedManualMinutes == nil)
                }
                .onAppear {
                    if customHoursText.isEmpty {
                        customHoursText = Self.hoursDecimalString(for: durationMinutes)
                    }
                }
            }
        }
    }

    private var presetSelectionBinding: Binding<Int> {
        Binding(
            get: { isPreset && !isCustomExpanded ? durationMinutes : -1 },
            set: { newValue in
                if newValue == -1 {
                    isCustomExpanded = true
                    customHoursText = Self.hoursDecimalString(for: durationMinutes)
                } else {
                    isCustomExpanded = false
                    durationMinutes = newValue
                }
            }
        )
    }

    private var customOptionLabel: String {
        if !isPreset {
            return "\(String(localized: "duration.custom")) (\(Self.formatted(minutes: durationMinutes)))"
        }
        return String(localized: "duration.custom")
    }

    private var parsedManualMinutes: Int? {
        let normalized = customHoursText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let hours = Double(normalized), hours > 0 else { return nil }
        return max(1, Int((hours * 60.0).rounded()))
    }

    private func applyManualHours() {
        guard let minutes = parsedManualMinutes else { return }
        durationMinutes = min(minutes, 1440)
        isCustomExpanded = false
    }

    static func hoursDecimalString(for minutes: Int) -> String {
        let hours = Double(minutes) / 60.0
        if hours.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(hours))
        }
        return String(format: "%.2g", hours)
    }

    static func formatted(minutes: Int) -> String {
        let minUnit = String(localized: "unit.minute_short")
        let hourUnit = String(localized: "unit.hour_short")
        if minutes < 60 {
            return "\(minutes) \(minUnit)"
        }
        let hours = minutes / 60
        let rem = minutes % 60
        if rem == 0 {
            return "\(hours) \(hourUnit)"
        }
        return "\(hours) \(hourUnit) \(rem) \(minUnit)"
    }
}
