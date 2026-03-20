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
                Section("Basics") {
                    TextField("Title", text: $draft.customTitle)

                    Picker("Event type", selection: $draft.eventTypeId) {
                        Text("No type").tag(Optional<Int64>.none)
                        ForEach(eventTypes) { eventType in
                            Text(eventType.title).tag(Optional(eventType.id))
                        }
                    }
                }

                Section("Schedule") {
                    DatePicker(
                        "Start",
                        selection: $draft.startAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    Stepper(value: $draft.durationMinutes, in: 15...720, step: 15) {
                        Text("Duration: \(draft.durationMinutes) min")
                    }

                    Stepper(value: $draft.reminderMinutes, in: 0...180, step: 5) {
                        Text(reminderLabel)
                    }
                }

                Section("Appearance") {
                    Picker("Color", selection: customColorBinding) {
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

                Section("Notes") {
                    TextField("Optional note", text: $draft.note, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let onDelete {
                    Section {
                        Button("Delete event", role: .destructive, action: onDelete)
                    }
                }
            }
            .navigationTitle(draft.id == nil ? "New event" : "Edit event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: onSave)
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

    private var reminderLabel: String {
        draft.reminderMinutes == 0 ? "No reminder" : "Reminder: \(draft.reminderMinutes) min before"
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
