import SwiftUI

struct OptionEditorView: View {
    static let maxFieldsPerOption = 5

    @State private var name: String
    @State private var fields: [EditableOptionField]

    let existingOption: TemplateOption?
    let onSave: (String, [OptionField]) async -> Void
    let onDelete: (() async -> Void)?
    let onCancel: () -> Void

    init(
        initial: TemplateOption?,
        onSave: @escaping (String, [OptionField]) async -> Void,
        onDelete: (() async -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) {
        self.existingOption = initial
        _name = State(initialValue: initial?.name ?? "")
        _fields = State(initialValue: initial?.fields.map(EditableOptionField.init) ?? [])
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("editor.basics") {
                    TextField("options.name_placeholder", text: $name)
                }

                Section {
                    ForEach($fields) { $field in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(field.fieldType.titleKey, systemImage: field.fieldType.systemImage)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.tint)
                                Spacer()
                            }

                            TextField("options.field_label_placeholder", text: $field.label)
                                .font(.subheadline)

                            if field.fieldType == .durationOverride {
                                DurationPickerRow(durationMinutes: $field.defaultDurationMinutes)
                            } else if field.fieldType == .variantText {
                                TextField("options.variant_text_placeholder", text: $field.defaultTextValue, axis: .vertical)
                                    .lineLimit(2...4)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        fields.remove(atOffsets: offsets)
                    }

                    if fields.count < Self.maxFieldsPerOption {
                        Menu {
                            ForEach(OptionFieldType.allCases) { fieldType in
                                Button {
                                    fields.append(EditableOptionField.make(type: fieldType))
                                } label: {
                                    Label(fieldType.titleKey, systemImage: fieldType.systemImage)
                                }
                            }
                        } label: {
                            Label("options.add_field", systemImage: "plus.circle")
                        }
                    }
                } header: {
                    Text(String(format: String(localized: "options.fields_header"), fields.count, Self.maxFieldsPerOption))
                }

                if let onDelete {
                    Section {
                        Button("options.delete_button", role: .destructive) {
                            Task { await onDelete() }
                        }
                    }
                }
            }
            .navigationTitle(
                existingOption == nil
                    ? LocalizedStringKey("options.new_title")
                    : LocalizedStringKey("options.edit_title")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.save") {
                        let resolvedName = name.nilIfBlank ?? "Option"
                        let domainFields = fields.enumerated().map { idx, item in
                            item.asDomain(optionId: existingOption?.id ?? 0, sortOrder: idx)
                        }
                        Task { await onSave(resolvedName, domainFields) }
                    }
                }
            }
        }
    }
}

private struct EditableOptionField: Identifiable {
    let id = UUID()
    let databaseId: Int64
    var fieldType: OptionFieldType
    var label: String
    var defaultDurationMinutes: Int
    var defaultTextValue: String

    init(field: OptionField) {
        self.databaseId = field.id
        self.fieldType = field.fieldType
        self.label = field.label ?? ""
        self.defaultDurationMinutes = field.defaultDurationMinutes ?? 60
        self.defaultTextValue = field.defaultTextValue ?? ""
    }

    init(databaseId: Int64, fieldType: OptionFieldType, label: String, defaultDurationMinutes: Int, defaultTextValue: String) {
        self.databaseId = databaseId
        self.fieldType = fieldType
        self.label = label
        self.defaultDurationMinutes = defaultDurationMinutes
        self.defaultTextValue = defaultTextValue
    }

    static func make(type: OptionFieldType) -> EditableOptionField {
        EditableOptionField(
            databaseId: 0,
            fieldType: type,
            label: "",
            defaultDurationMinutes: 60,
            defaultTextValue: ""
        )
    }

    func asDomain(optionId: Int64, sortOrder: Int) -> OptionField {
        OptionField(
            id: databaseId,
            optionId: optionId,
            fieldType: fieldType,
            sortOrder: sortOrder,
            label: label.nilIfBlank,
            defaultDurationMinutes: fieldType == .durationOverride ? defaultDurationMinutes : nil,
            defaultTextValue: fieldType == .variantText ? defaultTextValue.nilIfBlank : nil,
            defaultLocationId: nil,
            photoPath: nil
        )
    }
}

extension OptionFieldType {
    var titleKey: LocalizedStringKey {
        switch self {
        case .variantText: return "option.field.variant_text"
        case .durationOverride: return "option.field.duration_override"
        case .photo: return "option.field.photo"
        case .geoLocation: return "option.field.geo_location"
        case .client: return "option.field.client"
        }
    }

    var systemImage: String {
        switch self {
        case .variantText: return "text.alignleft"
        case .durationOverride: return "timer"
        case .photo: return "photo"
        case .geoLocation: return "mappin.and.ellipse"
        case .client: return "person"
        }
    }
}
