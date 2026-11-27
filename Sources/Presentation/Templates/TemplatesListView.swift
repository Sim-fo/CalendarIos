import SwiftUI

struct TemplatesListView: View {
    @StateObject private var viewModel: TemplatesListViewModel
    private let optionRepository: (any OptionRepository)?
    @State private var editingDraft: EventTypeDraft?
    @State private var templatePendingDelete: EventTypeWithCount?

    init(repository: any EventTypeRepository, optionRepository: (any OptionRepository)? = nil) {
        _viewModel = StateObject(wrappedValue: TemplatesListViewModel(repository: repository))
        self.optionRepository = optionRepository
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.templates.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.templates.isEmpty {
                ContentUnavailableView(
                    "templates.empty.title",
                    systemImage: "square.stack.3d.up",
                    description: Text("templates.empty.description")
                )
            } else {
                List {
                    ForEach(viewModel.templates) { item in
                        Button {
                            editingDraft = EventTypeDraft(eventType: item.eventType)
                        } label: {
                            TemplateListRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                templatePendingDelete = item
                            } label: {
                                Label("common.delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("feature.templates.title")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingDraft = EventTypeDraft.empty(defaultColorHex: nextSuggestedColorHex())
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: editorBinding) { box in
            TemplateEditorView(
                initialDraft: box.draft,
                existingEventCount: eventCount(for: box.draft.id),
                optionRepository: optionRepository,
                onSave: { draft in
                    let saved = await viewModel.save(draft)
                    if saved != nil {
                        editingDraft = nil
                    }
                    return saved != nil
                },
                onDelete: box.draft.id == nil ? nil : { deleteLinked in
                    if let item = viewModel.templates.first(where: { $0.id == box.draft.id }) {
                        await viewModel.delete(item, deleteLinkedEvents: deleteLinked)
                    }
                    editingDraft = nil
                },
                onCancel: {
                    editingDraft = nil
                }
            )
        }
        .alert(
            deleteAlertTitle,
            isPresented: Binding(
                get: { templatePendingDelete != nil },
                set: { if !$0 { templatePendingDelete = nil } }
            ),
            presenting: templatePendingDelete
        ) { item in
            if item.eventCount > 0 {
                Button("templates.delete_with_events", role: .destructive) {
                    Task { await viewModel.delete(item, deleteLinkedEvents: true) }
                }
                Button("templates.delete_keep_events") {
                    Task { await viewModel.delete(item, deleteLinkedEvents: false) }
                }
            } else {
                Button("common.delete", role: .destructive) {
                    Task { await viewModel.delete(item, deleteLinkedEvents: false) }
                }
            }
            Button("common.cancel", role: .cancel) {}
        } message: { item in
            if item.eventCount > 0 {
                Text(
                    String(
                        format: String(localized: "templates.delete_with_events_message"),
                        item.eventType.title,
                        item.eventCount
                    )
                )
            } else {
                Text(
                    String(
                        format: String(localized: "templates.delete_confirm_message"),
                        item.eventType.title
                    )
                )
            }
        }
        .alert(
            "common.error_title",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } }
            )
        ) {
            Button("common.ok") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? String(localized: "common.unknown_error"))
        }
        .task {
            await viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .calendarDataDidChange)) { _ in
            Task { await viewModel.load() }
        }
    }

    private var deleteAlertTitle: LocalizedStringKey {
        if let item = templatePendingDelete, item.eventCount > 0 {
            return "templates.delete_with_events_title"
        }
        return "templates.delete_title"
    }

    private var editorBinding: Binding<DraftSheetBox?> {
        Binding(
            get: { editingDraft.map { DraftSheetBox(draft: $0) } },
            set: { editingDraft = $0?.draft }
        )
    }

    private func eventCount(for id: Int64?) -> Int {
        guard let id else { return 0 }
        return viewModel.templates.first(where: { $0.id == id })?.eventCount ?? 0
    }

    private func nextSuggestedColorHex() -> Int {
        let used = Set(viewModel.templates.map { $0.eventType.colorHex & 0x00FFFFFF })
        if let unused = CalendarColor.pastelPresets.first(where: { !used.contains($0 & 0x00FFFFFF) }) {
            return unused
        }
        return CalendarColor.pastelPresets[viewModel.templates.count % CalendarColor.pastelPresets.count]
    }
}

private struct DraftSheetBox: Identifiable {
    let id = UUID()
    let draft: EventTypeDraft
}

struct TemplateListRow: View {
    let item: EventTypeWithCount
    var isHighlighted: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(calendarHex: item.eventType.colorHex))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.eventType.title)
                    .font(.body.weight(isHighlighted ? .semibold : .regular))
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Text(DurationPickerRow.formatted(minutes: item.eventType.defaultDurationMinutes))
                    if item.eventCount > 0 {
                        Text("·")
                        Text(String(format: String(localized: "templates.events_count"), item.eventCount))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if isHighlighted {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
