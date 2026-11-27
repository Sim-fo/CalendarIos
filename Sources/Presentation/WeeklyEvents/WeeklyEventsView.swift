import SwiftUI

@MainActor
final class WeeklyEventsListViewModel: ObservableObject {
    @Published private(set) var events: [WeeklyRecurringItem] = []
    @Published private(set) var templates: [EventType] = []
    @Published var errorMessage: String?

    private let weeklyRepository: any WeeklyRecurringRepository
    private let eventTypeRepository: any EventTypeRepository

    init(
        weeklyRepository: any WeeklyRecurringRepository,
        eventTypeRepository: any EventTypeRepository
    ) {
        self.weeklyRepository = weeklyRepository
        self.eventTypeRepository = eventTypeRepository
    }

    func load() async {
        do {
            templates = try await eventTypeRepository.fetchEventTypes()
            events = try await weeklyRepository.fetchWeeklyEvents()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func template(for id: Int64?) -> EventType? {
        guard let id else { return nil }
        return templates.first(where: { $0.id == id })
    }

    func save(
        id: Int64?,
        templateId: Int64?,
        customTitle: String?,
        customColorHex: Int?,
        reminderMinutes: Int,
        slots: [WeeklyRecurringSlot]
    ) async -> Bool {
        do {
            var resolvedTitle = customTitle?.nilIfBlank
            if templateId == nil && resolvedTitle == nil {
                let existing = events.compactMap(\.customTitle)
                resolvedTitle = NameGenerator.generateNextName(existingNames: existing)
            }
            _ = try await weeklyRepository.upsertWeeklyEvent(
                id: id,
                templateId: templateId,
                customTitle: resolvedTitle,
                customColorHex: customColorHex,
                reminderMinutes: reminderMinutes,
                slots: slots
            )
            events = try await weeklyRepository.fetchWeeklyEvents()
            NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ item: WeeklyRecurringItem) async {
        do {
            try await weeklyRepository.deleteWeeklyEvent(id: item.id)
            events = try await weeklyRepository.fetchWeeklyEvents()
            NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct WeeklyEventsListView: View {
    @StateObject private var viewModel: WeeklyEventsListViewModel
    @State private var editingItem: WeeklyRecurringItem?
    @State private var isCreatingNew = false

    init(dependencies: CalendarDependencies) {
        _viewModel = StateObject(
            wrappedValue: WeeklyEventsListViewModel(
                weeklyRepository: dependencies.featureRepository,
                eventTypeRepository: dependencies.eventRepository
            )
        )
    }

    var body: some View {
        Group {
            if viewModel.events.isEmpty {
                ContentUnavailableView(
                    "weekly_events.empty.title",
                    systemImage: "calendar.badge.clock",
                    description: Text("weekly_events.empty.subtitle")
                )
            } else {
                List {
                    ForEach(viewModel.events) { item in
                        let template = viewModel.template(for: item.templateId)
                        let title = item.customTitle?.nilIfBlank ?? template?.title ?? "Untitled"
                        let colorHex = item.customColorHex ?? template?.colorHex ?? CalendarColor.defaultEventHex

                        Button {
                            editingItem = item
                        } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(calendarHex: colorHex))
                                    .frame(width: 24, height: 24)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    Text(slotsSummary(for: item.slots))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await viewModel.delete(item) }
                            } label: {
                                Label("common.delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("feature.weekly_events.title")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCreatingNew = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreatingNew) {
            WeeklyRecurringEventEditorView(
                initial: nil,
                templates: viewModel.templates
            ) { templateId, customTitle, colorHex, reminder, slots in
                if await viewModel.save(
                    id: nil,
                    templateId: templateId,
                    customTitle: customTitle,
                    customColorHex: colorHex,
                    reminderMinutes: reminder,
                    slots: slots
                ) {
                    isCreatingNew = false
                }
            } onDelete: {
                isCreatingNew = false
            } onCancel: {
                isCreatingNew = false
            }
        }
        .sheet(item: $editingItem) { item in
            WeeklyRecurringEventEditorView(
                initial: item,
                templates: viewModel.templates
            ) { templateId, customTitle, colorHex, reminder, slots in
                if await viewModel.save(
                    id: item.id,
                    templateId: templateId,
                    customTitle: customTitle,
                    customColorHex: colorHex,
                    reminderMinutes: reminder,
                    slots: slots
                ) {
                    editingItem = nil
                }
            } onDelete: {
                await viewModel.delete(item)
                editingItem = nil
            } onCancel: {
                editingItem = nil
            }
        }
        .task {
            await viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .calendarDataDidChange)) { _ in
            Task { await viewModel.load() }
        }
    }

    private func slotsSummary(for slots: [WeeklyRecurringSlot]) -> String {
        guard !slots.isEmpty else { return String(localized: "weekly_events.no_slots") }
        return slots.map { slot in
            "\(ISOWeekdayFormatter.shortName(for: slot.dayOfWeek)) \(slot.startTime)"
        }.joined(separator: ", ")
    }
}

struct WeeklyRecurringEventEditorView: View {
    @State private var selectedTemplateId: Int64?
    @State private var customTitle: String
    @State private var customColorHex: Int
    @State private var reminderMinutes: Int
    @State private var slots: [EditableWeeklySlot]

    let existingItem: WeeklyRecurringItem?
    let templates: [EventType]
    let onSave: (Int64?, String?, Int?, Int, [WeeklyRecurringSlot]) async -> Void
    let onDelete: () async -> Void
    let onCancel: () -> Void

    private static let reminderOptions: [Int] = [0, 5, 10, 15, 30, 60, 120, 1440]

    init(
        initial: WeeklyRecurringItem?,
        templates: [EventType],
        onSave: @escaping (Int64?, String?, Int?, Int, [WeeklyRecurringSlot]) async -> Void,
        onDelete: @escaping () async -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.existingItem = initial
        self.templates = templates
        _selectedTemplateId = State(initialValue: initial?.templateId)
        _customTitle = State(initialValue: initial?.customTitle ?? "")
        _customColorHex = State(initialValue: initial?.customColorHex ?? CalendarColor.defaultEventHex)
        _reminderMinutes = State(initialValue: initial?.reminderMinutes ?? 10)
        if let initialSlots = initial?.slots, !initialSlots.isEmpty {
            _slots = State(initialValue: initialSlots.map(EditableWeeklySlot.init))
        } else {
            _slots = State(initialValue: [EditableWeeklySlot.defaultSlot()])
        }
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("editor.basics") {
                    Picker("editor.event_type", selection: $selectedTemplateId) {
                        Text("weekly_events.unique_mode").tag(Optional<Int64>.none)
                        ForEach(templates) { tpl in
                            Text(tpl.title).tag(Optional(tpl.id))
                        }
                    }

                    if selectedTemplateId == nil {
                        TextField("editor.title_placeholder", text: $customTitle)
                        ColorSwatchPickerView(selectedColorHex: $customColorHex, useExtendedPresets: true)
                    }

                    Picker("editor.reminder_label", selection: $reminderMinutes) {
                        ForEach(Self.reminderOptions, id: \.self) { mins in
                            Text(ReminderFormatter.label(for: mins)).tag(mins)
                        }
                    }
                }

                Section {
                    ForEach($slots) { $slot in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Picker("weekly_events.day", selection: $slot.dayOfWeek) {
                                    ForEach(1...7, id: \.self) { isoDay in
                                        Text(ISOWeekdayFormatter.fullName(for: isoDay)).tag(isoDay)
                                    }
                                }
                                .labelsHidden()

                                Spacer()

                                DatePicker(
                                    "",
                                    selection: $slot.timeDate,
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                            }

                            DurationPickerRow(durationMinutes: $slot.durationMinutes)

                            TextField("editor.note_placeholder", text: $slot.note)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        slots.remove(atOffsets: offsets)
                    }
                    .onMove { from, to in
                        slots.move(fromOffsets: from, toOffset: to)
                    }

                    Button {
                        let defaultDur = templates.first(where: { $0.id == selectedTemplateId })?.defaultDurationMinutes ?? 60
                        slots.append(EditableWeeklySlot.defaultSlot(duration: defaultDur))
                    } label: {
                        Label("weekly_events.add_slot", systemImage: "plus.circle")
                    }
                } header: {
                    Text("weekly_events.slots_section")
                }

                if existingItem != nil {
                    Section {
                        Button("weekly_events.delete_button", role: .destructive) {
                            Task { await onDelete() }
                        }
                    }
                }
            }
            .navigationTitle(
                existingItem == nil
                    ? LocalizedStringKey("weekly_events.new_title")
                    : LocalizedStringKey("weekly_events.edit_title")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.save") {
                        let domainSlots = slots.enumerated().map { index, slot in
                            slot.asDomain(weeklyEventId: existingItem?.id ?? 0, sortOrder: index)
                        }
                        Task {
                            await onSave(
                                selectedTemplateId,
                                selectedTemplateId == nil ? customTitle : nil,
                                selectedTemplateId == nil ? customColorHex : nil,
                                reminderMinutes,
                                domainSlots
                            )
                        }
                    }
                    .disabled(slots.isEmpty)
                }
            }
        }
    }
}

private struct EditableWeeklySlot: Identifiable {
    let id = UUID()
    var dayOfWeek: Int
    var timeDate: Date
    var durationMinutes: Int
    var note: String

    init(slot: WeeklyRecurringSlot) {
        self.dayOfWeek = slot.dayOfWeek
        let hm = slot.hourAndMinute
        self.timeDate = Calendar.current.dateBySettingHour(hm.hour, minute: hm.minute, on: Date())
        self.durationMinutes = slot.durationMinutes
        self.note = slot.note ?? ""
    }

    init(dayOfWeek: Int, timeDate: Date, durationMinutes: Int, note: String) {
        self.dayOfWeek = dayOfWeek
        self.timeDate = timeDate
        self.durationMinutes = durationMinutes
        self.note = note
    }

    static func defaultSlot(duration: Int = 60) -> EditableWeeklySlot {
        EditableWeeklySlot(
            dayOfWeek: 1,
            timeDate: Calendar.current.dateBySettingHour(9, minute: 0, on: Date()),
            durationMinutes: duration,
            note: ""
        )
    }

    func asDomain(weeklyEventId: Int64, sortOrder: Int) -> WeeklyRecurringSlot {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: timeDate)
        let timeStr = String(format: "%02d:%02d", comps.hour ?? 9, comps.minute ?? 0)
        return WeeklyRecurringSlot(
            id: 0,
            weeklyEventId: weeklyEventId,
            dayOfWeek: dayOfWeek,
            startTime: timeStr,
            durationMinutes: durationMinutes,
            note: note.nilIfBlank,
            sortOrder: sortOrder
        )
    }
}

enum ISOWeekdayFormatter {
    static func shortName(for isoDay: Int) -> String {
        // Calendar.shortStandaloneWeekdaySymbols: 0=Sun, 1=Mon ... 6=Sat
        let symbols = Calendar.current.shortStandaloneWeekdaySymbols
        let index = isoDay == 7 ? 0 : min(max(isoDay, 1), 6)
        return symbols[index].capitalized
    }

    static func fullName(for isoDay: Int) -> String {
        let symbols = Calendar.current.standaloneWeekdaySymbols
        let index = isoDay == 7 ? 0 : min(max(isoDay, 1), 6)
        return symbols[index].capitalized
    }
}
