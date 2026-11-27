import SwiftUI

struct EventEditorView: View {
    @Binding var draft: EventDraft
    let eventTypes: [EventType]
    let isSaving: Bool
    let onSave: () -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("editor.basics") {
                    TextField("editor.title_placeholder", text: $draft.customTitle)

                    Picker("editor.event_type", selection: $draft.eventTypeId) {
                        Text("editor.no_type").tag(Optional<Int64>.none)
                        ForEach(eventTypes) { eventType in
                            Text(eventType.title).tag(Optional(eventType.id))
                        }
                    }
                }

                Section("editor.schedule") {
                    DatePicker(
                        "editor.start",
                        selection: $draft.startAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    Stepper(value: $draft.durationMinutes, in: 15...720, step: 15) {
                        Text(String(format: String(localized: "editor.duration_minutes"), draft.durationMinutes))
                    }

                    Stepper(value: $draft.reminderMinutes, in: 0...180, step: 5) {
                        if draft.reminderMinutes == 0 {
                            Text("editor.no_reminder")
                        } else {
                            Text(String(format: String(localized: "editor.reminder_minutes"), draft.reminderMinutes))
                        }
                    }
                }

                Section("editor.appearance") {
                    Picker("editor.color", selection: customColorBinding) {
                        ForEach(CalendarColor.presetColors, id: \.self) { colorHex in
                            HStack {
                                Circle()
                                    .fill(Color(calendarHex: colorHex))
                                    .frame(width: 14, height: 14)
                                Text(colorName(for: colorHex))
                            }
                            .tag(Optional<Int>.some(colorHex))
                        }
                    }
                }

                Section("editor.notes") {
                    TextField("editor.note_placeholder", text: $draft.note, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let onDelete {
                    Section {
                        Button("editor.delete_event", role: .destructive, action: onDelete)
                    }
                }
            }
            .navigationTitle(draft.id == nil ? LocalizedStringKey("editor.new_title") : LocalizedStringKey("editor.edit_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel", action: onCancel)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.save", action: onSave)
                        .disabled(isSaving || !canSave)
                }
            }
        }
    }

    private var customColorBinding: Binding<Int?> {
        Binding(
            get: { draft.customColorHex },
            set: { draft.customColorHex = $0 }
        )
    }

    private var canSave: Bool {
        draft.customTitle.nilIfBlank != nil || draft.eventTypeId != nil
    }

    private func colorName(for hex: Int) -> String {
        switch hex {
        case 0xFF3A7AFE: return "Blue"
        case 0xFF11A36A: return "Green"
        case 0xFFEF6C3E: return "Orange"
        case 0xFFD44C8D: return "Rose"
        case 0xFF6B58D6: return "Indigo"
        default: return "Custom"
        }
    }
}
