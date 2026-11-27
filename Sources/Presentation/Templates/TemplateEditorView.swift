import SwiftUI

struct TemplateEditorView: View {
    static let maxOptionsPerTemplate = 10

    @State private var draft: EventTypeDraft
    @State private var isSaving = false
    @State private var isShowingDeleteConfirmation = false
    @State private var options: [TemplateOption] = []
    @State private var editingOption: TemplateOption?
    @State private var isCreatingOption = false

    let existingEventCount: Int
    let optionRepository: (any OptionRepository)?
    let onSave: (EventTypeDraft) async -> Bool
    let onDelete: ((Bool) async -> Void)?
    let onCancel: () -> Void

    private static let reminderOptions: [Int] = [0, 5, 10, 15, 30, 60, 120, 1440, 2880]

    init(
        initialDraft: EventTypeDraft,
        existingEventCount: Int = 0,
        optionRepository: (any OptionRepository)? = nil,
        onSave: @escaping (EventTypeDraft) async -> Bool,
        onDelete: ((Bool) async -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: initialDraft)
        self.existingEventCount = existingEventCount
        self.optionRepository = optionRepository
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("templates.editor.name_placeholder", text: $draft.title)
                } header: {
                    Text("editor.basics")
                } footer: {
                    Text("templates.editor.auto_name_hint")
                }

                Section("editor.schedule") {
                    DurationPickerRow(durationMinutes: $draft.defaultDurationMinutes)

                    Picker("editor.reminder_label", selection: $draft.notifyBeforeMinutes) {
                        ForEach(Self.reminderOptions, id: \.self) { minutes in
                            Text(ReminderFormatter.label(for: minutes)).tag(minutes)
                        }
                    }
                }

                Section("editor.appearance") {
                    ColorSwatchPickerView(selectedColorHex: $draft.colorHex, useExtendedPresets: true)
                }

                if let templateId = draft.id, let optionRepository {
                    Section {
                        ForEach(options) { option in
                            Button {
                                editingOption = option
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option.name)
                                            .foregroundStyle(.primary)
                                        if !option.fields.isEmpty {
                                            Text(String(format: String(localized: "options.fields_count"), option.fields.count))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task {
                                        try? await optionRepository.deleteOption(id: option.id)
                                        await reloadOptions(templateId: templateId)
                                    }
                                } label: {
                                    Label("common.delete", systemImage: "trash")
                                }
                            }
                        }

                        if options.count < Self.maxOptionsPerTemplate {
                            Button {
                                isCreatingOption = true
                            } label: {
                                Label("options.add_option", systemImage: "plus.circle")
                            }
                        }
                    } header: {
                        Text(String(format: String(localized: "options.section_header"), options.count, Self.maxOptionsPerTemplate))
                    }
                }

                if onDelete != nil {
                    Section {
                        Button("templates.delete_button", role: .destructive) {
                            isShowingDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(
                draft.id == nil
                    ? LocalizedStringKey("templates.editor.new_title")
                    : LocalizedStringKey("templates.editor.edit_title")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel", action: onCancel)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.save") {
                        Task {
                            isSaving = true
                            _ = await onSave(draft)
                            isSaving = false
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .task {
                if let templateId = draft.id {
                    await reloadOptions(templateId: templateId)
                }
            }
            .sheet(isPresented: $isCreatingOption) {
                if let templateId = draft.id, let optionRepository {
                    OptionEditorView(initial: nil) { name, fields in
                        _ = try? await optionRepository.upsertOption(
                            id: nil,
                            eventTypeId: templateId,
                            name: name,
                            description: nil,
                            fields: fields
                        )
                        await reloadOptions(templateId: templateId)
                        isCreatingOption = false
                    } onCancel: {
                        isCreatingOption = false
                    }
                }
            }
            .sheet(item: $editingOption) { option in
                if let templateId = draft.id, let optionRepository {
                    OptionEditorView(
                        initial: option,
                        onSave: { name, fields in
                            _ = try? await optionRepository.upsertOption(
                                id: option.id,
                                eventTypeId: templateId,
                                name: name,
                                description: nil,
                                fields: fields
                            )
                            await reloadOptions(templateId: templateId)
                            editingOption = nil
                        },
                        onDelete: {
                            try? await optionRepository.deleteOption(id: option.id)
                            await reloadOptions(templateId: templateId)
                            editingOption = nil
                        },
                        onCancel: {
                            editingOption = nil
                        }
                    )
                }
            }
            .alert(
                existingEventCount > 0 ? "templates.delete_with_events_title" : "templates.delete_title",
                isPresented: $isShowingDeleteConfirmation
            ) {
                if existingEventCount > 0 {
                    Button("templates.delete_with_events", role: .destructive) {
                        Task { await onDelete?(true) }
                    }
                    Button("templates.delete_keep_events") {
                        Task { await onDelete?(false) }
                    }
                } else {
                    Button("common.delete", role: .destructive) {
                        Task { await onDelete?(false) }
                    }
                }
                Button("common.cancel", role: .cancel) {}
            } message: {
                if existingEventCount > 0 {
                    Text(
                        String(
                            format: String(localized: "templates.delete_with_events_message"),
                            draft.title,
                            existingEventCount
                        )
                    )
                } else {
                    Text(
                        String(
                            format: String(localized: "templates.delete_confirm_message"),
                            draft.title
                        )
                    )
                }
            }
        }
    }

    private func reloadOptions(templateId: Int64) async {
        guard let optionRepository else { return }
        options = (try? await optionRepository.fetchOptions(forEventTypeId: templateId)) ?? []
    }
}

enum ReminderFormatter {
    static func label(for minutes: Int) -> String {
        switch minutes {
        case 0:
            return String(localized: "reminder.at_start")
        case 1440:
            return String(localized: "reminder.one_day_before")
        case 2880:
            return String(localized: "reminder.two_days_before")
        default:
            return String(format: String(localized: "editor.reminder_minutes"), minutes)
        }
    }
}
