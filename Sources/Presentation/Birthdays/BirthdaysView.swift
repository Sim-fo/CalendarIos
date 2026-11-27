import PhotosUI
import SwiftUI

@MainActor
final class BirthdaysListViewModel: ObservableObject {
    @Published private(set) var birthdays: [BirthdayItem] = []
    @Published var errorMessage: String?

    private let repository: any BirthdayRepository

    init(repository: any BirthdayRepository) {
        self.repository = repository
    }

    func load() async {
        do {
            birthdays = try await repository.fetchBirthdays()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(_ item: BirthdayItem, isNew: Bool) async -> Bool {
        do {
            _ = try await repository.upsertBirthday(item, isNew: isNew)
            birthdays = try await repository.fetchBirthdays()
            NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func toggleAcknowledge(_ item: BirthdayItem, year: Int) async {
        let nextYear: Int? = item.isAcknowledged(inYear: year) ? nil : year
        do {
            try await repository.acknowledgeBirthday(id: item.id, year: nextYear)
            birthdays = try await repository.fetchBirthdays()
            NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ item: BirthdayItem) async {
        do {
            MediaStorageService.deleteFile(named: item.photoPath)
            try await repository.deleteBirthday(id: item.id)
            birthdays = try await repository.fetchBirthdays()
            NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct BirthdaysListView: View {
    @StateObject private var viewModel: BirthdaysListViewModel
    @State private var editingBirthday: BirthdayItem?
    @State private var isCreatingNew = false

    init(repository: any BirthdayRepository) {
        _viewModel = StateObject(wrappedValue: BirthdaysListViewModel(repository: repository))
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    var body: some View {
        Group {
            if viewModel.birthdays.isEmpty {
                ContentUnavailableView(
                    "birthdays.empty.title",
                    systemImage: "gift",
                    description: Text("birthdays.empty.subtitle")
                )
            } else {
                List {
                    ForEach(viewModel.birthdays) { item in
                        birthdayRow(item)
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
        .navigationTitle("feature.birthdays.title")
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
            BirthdayEditorView(initial: nil) { saved in
                if await viewModel.save(saved, isNew: true) {
                    isCreatingNew = false
                }
            } onDelete: {
                isCreatingNew = false
            } onCancel: {
                isCreatingNew = false
            }
        }
        .sheet(item: $editingBirthday) { item in
            BirthdayEditorView(initial: item) { saved in
                if await viewModel.save(saved, isNew: false) {
                    editingBirthday = nil
                }
            } onDelete: {
                await viewModel.delete(item)
                editingBirthday = nil
            } onCancel: {
                editingBirthday = nil
            }
        }
        .task {
            await viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .calendarDataDidChange)) { _ in
            Task { await viewModel.load() }
        }
    }

    private func birthdayRow(_ item: BirthdayItem) -> some View {
        let ack = item.isAcknowledged(inYear: currentYear)

        return HStack(spacing: 12) {
            Button {
                editingBirthday = item
            } label: {
                HStack(spacing: 12) {
                    if let uiImage = MediaStorageService.loadImage(named: item.photoPath) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.orange.opacity(0.18))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: "gift.fill")
                                    .foregroundStyle(.orange)
                            }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)

                        HStack(spacing: 6) {
                            if let date = item.dateInYear(currentYear) {
                                Text(CalendarDateFormatter.shortDate(for: date, calendar: .current))
                            }
                            if let age = item.age(inYear: currentYear) {
                                Text("·")
                                Text(String(format: String(localized: "birthdays.age_turning"), age))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                Task { await viewModel.toggleAcknowledge(item, year: currentYear) }
            } label: {
                Image(systemName: ack ? "checkmark.seal.fill" : "checkmark.seal")
                    .foregroundStyle(ack ? Color.green : Color.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

struct BirthdayEditorView: View {
    @State private var name: String
    @State private var selectedDate: Date
    @State private var includeYear: Bool
    @State private var note: String
    @State private var contactPhone: String
    @State private var contactId: String?
    @State private var photoPath: String?
    @State private var remindWeekBefore: Bool
    @State private var remindAtStart: Bool
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var isShowingContactPicker = false

    let existingItem: BirthdayItem?
    let onSave: (BirthdayItem) async -> Void
    let onDelete: () async -> Void
    let onCancel: () -> Void

    init(
        initial: BirthdayItem?,
        onSave: @escaping (BirthdayItem) async -> Void,
        onDelete: @escaping () async -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.existingItem = initial
        _name = State(initialValue: initial?.name ?? "")
        _includeYear = State(initialValue: initial?.hasBirthYear ?? true)
        _note = State(initialValue: initial?.note ?? "")
        _contactPhone = State(initialValue: initial?.contactPhone ?? "")
        _contactId = State(initialValue: initial?.contactId)
        _photoPath = State(initialValue: initial?.photoPath)
        _remindWeekBefore = State(initialValue: initial?.remindWeekBefore ?? false)
        _remindAtStart = State(initialValue: initial?.remindAtStart ?? true)

        if let parsed = initial?.parsedComponents() {
            let year = parsed.year ?? Calendar.current.component(.year, from: Date())
            let date = Calendar.current.date(from: DateComponents(year: year, month: parsed.month, day: parsed.day)) ?? Date()
            _selectedDate = State(initialValue: date)
        } else {
            _selectedDate = State(initialValue: Date())
        }

        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        if let uiImage = MediaStorageService.loadImage(named: photoPath) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.orange.opacity(0.18))
                                .frame(width: 56, height: 56)
                                .overlay {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .font(.title2)
                                        .foregroundStyle(.orange)
                                }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            PhotosPicker(selection: $pickedPhotoItem, matching: .images) {
                                Text("common.choose_photo")
                                    .font(.subheadline.weight(.medium))
                            }

                            Button("contacts.import_from_contacts") {
                                isShowingContactPicker = true
                            }
                            .font(.subheadline)
                        }
                    }

                    TextField("birthdays.name_placeholder", text: $name)
                    TextField("clients.phone_placeholder", text: $contactPhone)
                        .keyboardType(.phonePad)
                }

                Section("birthdays.date_section") {
                    Toggle("birthdays.include_year", isOn: $includeYear)
                    DatePicker("birthdays.birth_date", selection: $selectedDate, displayedComponents: .date)
                }

                Section("editor.reminder_label") {
                    Toggle("birthdays.remind_on_day", isOn: $remindAtStart)
                    Toggle("birthdays.remind_week_before", isOn: $remindWeekBefore)
                }

                Section("editor.notes") {
                    TextField("editor.note_placeholder", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                if existingItem != nil {
                    Section {
                        Button("birthdays.delete_button", role: .destructive) {
                            Task { await onDelete() }
                        }
                    }
                }
            }
            .navigationTitle(
                existingItem == nil
                    ? LocalizedStringKey("birthdays.new_title")
                    : LocalizedStringKey("birthdays.edit_title")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.save") {
                        Task { await performSave() }
                    }
                    .disabled(name.nilIfBlank == nil)
                }
            }
            .sheet(isPresented: $isShowingContactPicker) {
                ContactPickerSheet { info in
                    if name.nilIfBlank == nil { name = info.fullName }
                    if let phone = info.phone { contactPhone = phone }
                    contactId = info.identifier
                    if let bday = info.birthdayComponents, let m = bday.month, let d = bday.day {
                        let y = bday.year ?? Calendar.current.component(.year, from: Date())
                        includeYear = bday.year != nil
                        if let date = Calendar.current.date(from: DateComponents(year: y, month: m, day: d)) {
                            selectedDate = date
                        }
                    }
                    if let imageData = info.imageData, let saved = try? MediaStorageService.saveImageData(imageData, prefix: "bday") {
                        photoPath = saved
                    }
                    isShowingContactPicker = false
                } onCancel: {
                    isShowingContactPicker = false
                }
            }
            .onChange(of: pickedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let saved = try? MediaStorageService.saveImageData(data, prefix: "bday") {
                        photoPath = saved
                    }
                }
            }
        }
    }

    private func performSave() async {
        guard let trimmedName = name.nilIfBlank else { return }
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
        let isoDate = BirthdayItem.formatISO(
            year: includeYear ? comps.year : nil,
            month: comps.month ?? 1,
            day: comps.day ?? 1
        )
        let item = BirthdayItem(
            id: existingItem?.id ?? 0,
            name: trimmedName,
            birthDate: isoDate,
            note: note.nilIfBlank,
            contactPhone: contactPhone.nilIfBlank,
            contactId: contactId,
            photoPath: photoPath,
            remindWeekBefore: remindWeekBefore,
            remindAtStart: remindAtStart,
            lastAcknowledgedYear: existingItem?.lastAcknowledgedYear
        )
        await onSave(item)
    }
}
