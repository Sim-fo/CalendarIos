import SwiftUI

@MainActor
final class TrackersListViewModel: ObservableObject {
    @Published private(set) var trackers: [TrackerItem] = []
    @Published var errorMessage: String?

    private let repository: any TrackerRepository

    init(repository: any TrackerRepository) {
        self.repository = repository
    }

    func load() async {
        do {
            trackers = try await repository.fetchTrackers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(
        id: Int64?,
        name: String,
        intervalDays: Int,
        createdDate: Date,
        lastResetDate: Date,
        colorHex: Int
    ) async -> Bool {
        errorMessage = nil
        do {
            var resolvedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if resolvedName.isEmpty {
                let existing = try await repository.fetchTrackers().map(\.name)
                resolvedName = NameGenerator.generateNextName(existingNames: existing)
            } else {
                let unique = try await repository.isTrackerNameUnique(resolvedName, excludingId: id)
                guard unique else {
                    errorMessage = String(localized: "trackers.error.duplicate_name")
                    return false
                }
            }

            _ = try await repository.upsertTracker(
                id: id,
                name: resolvedName,
                intervalDays: intervalDays,
                createdDate: createdDate,
                lastResetDate: lastResetDate,
                colorHex: colorHex
            )
            trackers = try await repository.fetchTrackers()
            NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func reset(_ tracker: TrackerItem) async {
        do {
            try await repository.resetTracker(id: tracker.id, at: Date())
            trackers = try await repository.fetchTrackers()
            NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ tracker: TrackerItem) async {
        do {
            try await repository.deleteTracker(id: tracker.id)
            trackers = try await repository.fetchTrackers()
            NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TrackersListView: View {
    @StateObject private var viewModel: TrackersListViewModel
    @State private var editingTracker: TrackerItem?
    @State private var isCreatingNew = false

    init(repository: any TrackerRepository) {
        _viewModel = StateObject(wrappedValue: TrackersListViewModel(repository: repository))
    }

    var body: some View {
        Group {
            if viewModel.trackers.isEmpty {
                ContentUnavailableView(
                    "trackers.empty.title",
                    systemImage: "repeat",
                    description: Text("trackers.empty.subtitle")
                )
            } else {
                List {
                    ForEach(viewModel.trackers) { tracker in
                        trackerRow(tracker)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await viewModel.delete(tracker) }
                                } label: {
                                    Label("common.delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("feature.trackers.title")
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
            TrackerEditorView(
                initial: nil,
                onSave: { name, interval, created, lastReset, colorHex in
                    let ok = await viewModel.save(
                        id: nil,
                        name: name,
                        intervalDays: interval,
                        createdDate: created,
                        lastResetDate: lastReset,
                        colorHex: colorHex
                    )
                    if ok { isCreatingNew = false }
                },
                onReset: nil,
                onDelete: nil,
                onCancel: { isCreatingNew = false }
            )
        }
        .sheet(item: $editingTracker) { tracker in
            TrackerEditorView(
                initial: tracker,
                onSave: { name, interval, created, lastReset, colorHex in
                    let ok = await viewModel.save(
                        id: tracker.id,
                        name: name,
                        intervalDays: interval,
                        createdDate: created,
                        lastResetDate: lastReset,
                        colorHex: colorHex
                    )
                    if ok { editingTracker = nil }
                },
                onReset: {
                    await viewModel.reset(tracker)
                    editingTracker = nil
                },
                onDelete: {
                    await viewModel.delete(tracker)
                    editingTracker = nil
                },
                onCancel: { editingTracker = nil }
            )
        }
        .alert(
            "common.error_title",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("common.ok") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task {
            await viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .calendarDataDidChange)) { _ in
            Task { await viewModel.load() }
        }
    }

    private func trackerRow(_ tracker: TrackerItem) -> some View {
        let passed = max(0, tracker.daysSinceReset())
        let isOverdue = tracker.isOverdue()
        let progress = min(1.0, Double(passed) / Double(max(tracker.intervalDays, 1)))

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    editingTracker = tracker
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(calendarHex: tracker.colorHex))
                            .frame(width: 12, height: 12)
                        Text(tracker.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button("trackers.reset") {
                    Task { await viewModel.reset(tracker) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            ProgressView(value: progress)
                .tint(isOverdue ? .red : Color(calendarHex: tracker.colorHex))

            HStack {
                Text(
                    isOverdue
                        ? String(format: String(localized: "trackers.overdue_status"), passed, tracker.intervalDays)
                        : String(format: String(localized: "trackers.progress_status"), passed, tracker.intervalDays)
                )
                .font(.caption)
                .foregroundStyle(isOverdue ? .red : .secondary)

                Spacer()

                Text(CalendarDateFormatter.shortDate(for: tracker.lastResetDate, calendar: .current))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TrackerEditorView: View {
    @State private var name: String
    @State private var intervalDays: Int
    @State private var createdDate: Date
    @State private var lastResetDate: Date
    @State private var colorHex: Int

    let isEditing: Bool
    let onSave: (String, Int, Date, Date, Int) async -> Void
    let onReset: (() async -> Void)?
    let onDelete: (() async -> Void)?
    let onCancel: () -> Void

    init(
        initial: TrackerItem?,
        onSave: @escaping (String, Int, Date, Date, Int) async -> Void,
        onReset: (() async -> Void)?,
        onDelete: (() async -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        let now = Date()
        _name = State(initialValue: initial?.name ?? "")
        _intervalDays = State(initialValue: initial?.intervalDays ?? 14)
        _createdDate = State(initialValue: initial?.createdDate ?? now)
        _lastResetDate = State(initialValue: initial?.lastResetDate ?? now)
        _colorHex = State(initialValue: initial?.colorHex ?? TrackerItem.defaultColorHex)
        self.isEditing = initial != nil
        self.onSave = onSave
        self.onReset = onReset
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("editor.basics") {
                    TextField("trackers.name_placeholder", text: $name)
                    Stepper(value: $intervalDays, in: 1...365) {
                        Text(String(format: String(localized: "trackers.interval_days"), intervalDays))
                    }
                    DatePicker("trackers.last_reset_date", selection: $lastResetDate, displayedComponents: .date)
                }

                Section("editor.appearance") {
                    ColorSwatchPickerView(selectedColorHex: $colorHex, useExtendedPresets: true)
                }

                if isEditing {
                    Section {
                        HStack {
                            Text("trackers.created_date")
                            Spacer()
                            Text(CalendarDateFormatter.longDate(for: createdDate, calendar: .current))
                                .foregroundStyle(.secondary)
                        }

                        if let onReset {
                            Button("trackers.reset_today") {
                                Task { await onReset() }
                            }
                        }
                    }

                    if let onDelete {
                        Section {
                            Button("trackers.delete_button", role: .destructive) {
                                Task { await onDelete() }
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? LocalizedStringKey("trackers.edit_title") : LocalizedStringKey("trackers.new_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.save") {
                        Task {
                            await onSave(name, intervalDays, createdDate, lastResetDate, colorHex)
                        }
                    }
                }
            }
        }
    }
}
