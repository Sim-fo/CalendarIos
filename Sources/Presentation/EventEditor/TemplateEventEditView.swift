import PhotosUI
import SwiftUI

struct TemplateEventEditView: View {
    @Binding var draft: EventDraft
    let eventTypes: [EventType]
    let featureRepository: GRDBFeatureRepository?
    let isSaving: Bool
    let onSave: ([EventOptionValue]) -> Void
    let onDelete: () -> Void
    let onEditTemplate: (EventType) -> Void
    let onCancel: () -> Void

    @State private var isShowingDeleteConfirmation = false
    @State private var options: [TemplateOption] = []
    @State private var clients: [ClientItem] = []
    @State private var locations: [LocationLinkItem] = []
    @State private var fieldValuesById: [Int64: EventOptionValue] = [:]
    @State private var pickedPhotoFieldId: Int64?
    @State private var pickedPhotoItem: PhotosPickerItem?

    private static let reminderOptions: [Int] = [0, 5, 10, 15, 30, 60, 120, 1440, 2880]

    private var selectedTemplate: EventType? {
        guard let id = draft.eventTypeId else { return nil }
        return eventTypes.first(where: { $0.id == id })
    }

    private var selectedOption: TemplateOption? {
        guard let optId = draft.selectedOptionId else { return nil }
        return options.first(where: { $0.id == optId })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("feature.templates.title") {
                    HStack(spacing: 12) {
                        if let selectedTemplate {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color(calendarHex: selectedTemplate.colorHex))
                                .frame(width: 22, height: 22)
                        }

                        Picker("editor.event_type", selection: templateSelectionBinding) {
                            ForEach(eventTypes) { type in
                                Text(type.title).tag(Optional(type.id))
                            }
                        }
                    }

                    if let selectedTemplate {
                        Button {
                            onEditTemplate(selectedTemplate)
                        } label: {
                            Label("event_edit.edit_template", systemImage: "pencil")
                        }
                    }
                }

                Section("editor.schedule") {
                    DatePicker(
                        "editor.start",
                        selection: $draft.startAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    DurationPickerRow(durationMinutes: $draft.durationMinutes)

                    Picker("editor.reminder_label", selection: $draft.reminderMinutes) {
                        ForEach(Self.reminderOptions, id: \.self) { minutes in
                            Text(ReminderFormatter.label(for: minutes)).tag(minutes)
                        }
                    }
                }

                if !options.isEmpty {
                    Section("options.picker_section") {
                        Picker("options.picker_label", selection: optionSelectionBinding) {
                            Text("options.not_selected").tag(Optional<Int64>.none)
                            ForEach(options) { option in
                                Text(option.name).tag(Optional(option.id))
                            }
                        }

                        if let selectedOption {
                            ForEach(selectedOption.fields) { field in
                                optionFieldRow(field)
                            }
                        }
                    }
                }

                Section("editor.notes") {
                    TextField("editor.note_placeholder", text: $draft.note, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Button("editor.delete_event", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                }
            }
            .navigationTitle("editor.edit_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel", action: onCancel)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.save") {
                        let activeFieldIds = Set(selectedOption?.fields.map(\.id) ?? [])
                        let valuesToSave = fieldValuesById.values.filter { activeFieldIds.contains($0.fieldId) }
                        onSave(Array(valuesToSave))
                    }
                    .disabled(isSaving || draft.eventTypeId == nil)
                }
            }
            .task(id: draft.eventTypeId) {
                await loadMetadata()
            }
            .onChange(of: pickedPhotoItem) { _, newItem in
                guard let newItem, let fieldId = pickedPhotoFieldId else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let saved = try? MediaStorageService.saveImageData(data, prefix: "opt") {
                        var current = valueForField(fieldId)
                        current.photoPath = saved
                        fieldValuesById[fieldId] = current
                    }
                }
            }
            .alert("event_edit.delete_confirm_title", isPresented: $isShowingDeleteConfirmation) {
                Button("common.delete", role: .destructive, action: onDelete)
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("event_edit.delete_confirm_message")
            }
        }
    }

    @ViewBuilder
    private func optionFieldRow(_ field: OptionField) -> some View {
        switch field.fieldType {
        case .durationOverride:
            if let overrideMins = field.defaultDurationMinutes {
                HStack {
                    Text(field.label ?? String(localized: "duration.label"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(DurationPickerRow.formatted(minutes: overrideMins))
                        .font(.subheadline.weight(.semibold))
                }
            }

        case .variantText:
            if let text = field.defaultTextValue, !text.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.label ?? String(localized: "option.field.variant_text"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(text)
                        .font(.body)
                }
            }

        case .client:
            Picker(
                field.label ?? String(localized: "option.field.client"),
                selection: Binding(
                    get: { fieldValuesById[field.id]?.clientId },
                    set: { newClientId in
                        var val = valueForField(field.id)
                        val.clientId = newClientId
                        fieldValuesById[field.id] = val
                    }
                )
            ) {
                Text("options.not_selected").tag(Optional<Int64>.none)
                ForEach(clients) { client in
                    Text(client.name).tag(Optional(client.id))
                }
            }

        case .geoLocation:
            Picker(
                field.label ?? String(localized: "option.field.geo_location"),
                selection: Binding(
                    get: { fieldValuesById[field.id]?.locationLabel ?? "" },
                    set: { newLabel in
                        var val = valueForField(field.id)
                        val.locationLabel = newLabel.nilIfBlank
                        fieldValuesById[field.id] = val
                    }
                )
            ) {
                Text("options.not_selected").tag("")
                ForEach(locations) { link in
                    Text(link.displayTitle).tag(link.displayTitle)
                }
            }

        case .photo:
            HStack {
                Text(field.label ?? String(localized: "option.field.photo"))
                Spacer()
                if let uiImage = MediaStorageService.loadImage(named: fieldValuesById[field.id]?.photoPath) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                PhotosPicker(selection: $pickedPhotoItem, matching: .images) {
                    Text("common.choose_photo")
                        .font(.subheadline)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    pickedPhotoFieldId = field.id
                })
            }
        }
    }

    private func valueForField(_ fieldId: Int64) -> EventOptionValue {
        fieldValuesById[fieldId] ?? EventOptionValue(
            id: 0,
            eventId: draft.id ?? 0,
            fieldId: fieldId,
            textValue: nil,
            photoPath: nil,
            clientId: nil,
            latitude: nil,
            longitude: nil,
            locationLabel: nil
        )
    }

    private func loadMetadata() async {
        guard let featureRepository, let typeId = draft.eventTypeId else { return }
        options = (try? await featureRepository.fetchOptions(forEventTypeId: typeId)) ?? []
        clients = (try? await featureRepository.fetchClients()) ?? []
        locations = (try? await featureRepository.fetchLocationLinks()) ?? []
        if let eventId = draft.id {
            let saved = (try? await featureRepository.fetchOptionValues(forEventId: eventId)) ?? []
            fieldValuesById = Dictionary(uniqueKeysWithValues: saved.map { ($0.fieldId, $0) })
        }
    }

    private var templateSelectionBinding: Binding<Int64?> {
        Binding(
            get: { draft.eventTypeId },
            set: { newId in
                draft.eventTypeId = newId
                draft.selectedOptionId = nil
                draft.selectedOptionName = nil
                if let newId, let matched = eventTypes.first(where: { $0.id == newId }) {
                    draft.customTitle = ""
                    draft.customColorHex = nil
                    draft.durationMinutes = matched.defaultDurationMinutes
                    draft.reminderMinutes = matched.notifyBeforeMinutes
                }
            }
        )
    }

    private var optionSelectionBinding: Binding<Int64?> {
        Binding(
            get: { draft.selectedOptionId },
            set: { newOptId in
                draft.selectedOptionId = newOptId
                if let newOptId, let opt = options.first(where: { $0.id == newOptId }) {
                    draft.selectedOptionName = opt.name
                    if let overrideDuration = opt.fields.first(where: { $0.fieldType == .durationOverride })?.defaultDurationMinutes {
                        draft.durationMinutes = overrideDuration
                    }
                } else {
                    draft.selectedOptionName = nil
                    if let selectedTemplate {
                        draft.durationMinutes = selectedTemplate.defaultDurationMinutes
                    }
                }
            }
        )
    }
}

struct UniqueEventEditView: View {
    @Binding var draft: EventDraft
    let isSaving: Bool
    let onSave: () -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    @StateObject private var audioManager: AudioNoteManager
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingAudioDeleteConfirm = false

    private static let reminderOptions: [Int] = [0, 5, 10, 15, 30, 60, 120, 1440, 2880]

    init(
        draft: Binding<EventDraft>,
        isSaving: Bool,
        onSave: @escaping () -> Void,
        onDelete: (() -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        _draft = draft
        self.isSaving = isSaving
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _audioManager = StateObject(wrappedValue: AudioNoteManager(initialFileName: draft.wrappedValue.audioNotePath))
    }

    private var colorHexBinding: Binding<Int> {
        Binding(
            get: { draft.customColorHex ?? CalendarColor.defaultEventHex },
            set: { draft.customColorHex = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("editor.title_placeholder", text: $draft.customTitle)
                } header: {
                    Text("editor.basics")
                } footer: {
                    Text("unique_event.auto_name_hint")
                }

                Section("editor.appearance") {
                    ColorSwatchPickerView(selectedColorHex: colorHexBinding, useExtendedPresets: true)
                }

                Section("editor.schedule") {
                    DatePicker(
                        "editor.start",
                        selection: $draft.startAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    DurationPickerRow(durationMinutes: $draft.durationMinutes)

                    Picker("editor.reminder_label", selection: $draft.reminderMinutes) {
                        ForEach(Self.reminderOptions, id: \.self) { minutes in
                            Text(ReminderFormatter.label(for: minutes)).tag(minutes)
                        }
                    }
                }

                Section("audio.section_title") {
                    HStack(spacing: 12) {
                        if audioManager.currentAudioFileName == nil || audioManager.isRecording {
                            Button {
                                audioManager.toggleRecording()
                            } label: {
                                Label(
                                    audioManager.isRecording
                                        ? LocalizedStringKey("audio.stop_recording")
                                        : LocalizedStringKey("audio.record"),
                                    systemImage: audioManager.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                                )
                                .foregroundStyle(audioManager.isRecording ? .red : .accentColor)
                            }
                            .buttonStyle(.borderless)
                        }

                        if audioManager.currentAudioFileName != nil && !audioManager.isRecording {
                            Button {
                                audioManager.togglePlayback()
                            } label: {
                                Label(
                                    audioManager.isPlaying
                                        ? LocalizedStringKey("audio.stop_playback")
                                        : LocalizedStringKey("audio.play"),
                                    systemImage: audioManager.isPlaying ? "stop.fill" : "play.fill"
                                )
                            }
                            .buttonStyle(.borderless)

                            Spacer()

                            Button(role: .destructive) {
                                isShowingAudioDeleteConfirm = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    if let audioError = audioManager.errorMessage {
                        Text(audioError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("editor.notes") {
                    TextField("editor.note_placeholder", text: $draft.note, axis: .vertical)
                        .lineLimit(3...6)
                }

                if onDelete != nil {
                    Section {
                        Button("editor.delete_event", role: .destructive) {
                            isShowingDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(
                draft.id == nil
                    ? LocalizedStringKey("unique_event.new_title")
                    : LocalizedStringKey("unique_event.edit_title")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel") {
                        audioManager.stopPlayback()
                        if audioManager.isRecording {
                            audioManager.stopRecording()
                        }
                        onCancel()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.save") {
                        if audioManager.isRecording {
                            audioManager.stopRecording()
                        }
                        audioManager.stopPlayback()
                        draft.audioNotePath = audioManager.currentAudioFileName
                        onSave()
                    }
                    .disabled(isSaving)
                }
            }
            .onChange(of: audioManager.currentAudioFileName) { _, newName in
                draft.audioNotePath = newName
            }
            .alert("event_edit.delete_confirm_title", isPresented: $isShowingDeleteConfirmation) {
                Button("common.delete", role: .destructive) {
                    audioManager.deleteAudio()
                    onDelete?()
                }
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("event_edit.delete_confirm_message")
            }
            .alert("audio.delete_title", isPresented: $isShowingAudioDeleteConfirm) {
                Button("common.delete", role: .destructive) {
                    audioManager.deleteAudio()
                }
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("audio.delete_message")
            }
        }
    }
}
