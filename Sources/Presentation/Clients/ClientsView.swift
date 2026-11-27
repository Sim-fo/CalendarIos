import PhotosUI
import SwiftUI

@MainActor
final class ClientsListViewModel: ObservableObject {
    @Published private(set) var clients: [ClientItem] = []
    @Published var searchQuery = ""
    @Published var errorMessage: String?

    private let repository: any ClientRepository

    init(repository: any ClientRepository) {
        self.repository = repository
    }

    var filteredClients: [ClientItem] {
        guard let q = searchQuery.nilIfBlank?.lowercased() else { return clients }
        return clients.filter {
            $0.name.lowercased().contains(q)
                || ($0.phone?.lowercased().contains(q) ?? false)
                || ($0.email?.lowercased().contains(q) ?? false)
                || ($0.note?.lowercased().contains(q) ?? false)
        }
    }

    func load() async {
        do {
            clients = try await repository.fetchClients()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(_ client: ClientItem, isNew: Bool) async -> Bool {
        do {
            _ = try await repository.upsertClient(client, isNew: isNew)
            clients = try await repository.fetchClients()
            NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ client: ClientItem) async {
        do {
            MediaStorageService.deleteFile(named: client.photoPath)
            try await repository.deleteClient(id: client.id)
            clients = try await repository.fetchClients()
            NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ClientsListView: View {
    @StateObject private var viewModel: ClientsListViewModel
    @State private var editingClient: ClientItem?
    @State private var isCreatingNew = false
    @Environment(\.openURL) private var openURL

    init(repository: any ClientRepository) {
        _viewModel = StateObject(wrappedValue: ClientsListViewModel(repository: repository))
    }

    var body: some View {
        Group {
            if viewModel.filteredClients.isEmpty {
                ContentUnavailableView(
                    "clients.empty.title",
                    systemImage: "person.2",
                    description: Text("clients.empty.subtitle")
                )
            } else {
                List {
                    ForEach(viewModel.filteredClients) { client in
                        clientRow(client)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await viewModel.delete(client) }
                                } label: {
                                    Label("common.delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .searchable(text: $viewModel.searchQuery, prompt: Text("clients.search_prompt"))
        .navigationTitle("feature.clients.title")
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
            ClientEditorView(initial: nil) { saved in
                if await viewModel.save(saved, isNew: true) {
                    isCreatingNew = false
                }
            } onDelete: {
                isCreatingNew = false
            } onCancel: {
                isCreatingNew = false
            }
        }
        .sheet(item: $editingClient) { client in
            ClientEditorView(initial: client) { saved in
                if await viewModel.save(saved, isNew: false) {
                    editingClient = nil
                }
            } onDelete: {
                await viewModel.delete(client)
                editingClient = nil
            } onCancel: {
                editingClient = nil
            }
        }
        .task {
            await viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .calendarDataDidChange)) { _ in
            Task { await viewModel.load() }
        }
    }

    private func clientRow(_ client: ClientItem) -> some View {
        HStack(spacing: 12) {
            Button {
                editingClient = client
            } label: {
                HStack(spacing: 12) {
                    if let uiImage = MediaStorageService.loadImage(named: client.photoPath) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.accentColor.opacity(0.16))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Text(String(client.name.prefix(1)).uppercased())
                                    .font(.headline)
                                    .foregroundStyle(.tint)
                            }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(client.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let phone = client.phone, !phone.isEmpty {
                            Text(phone)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let note = client.note, !note.isEmpty {
                            Text(note)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if let phone = client.phone?.nilIfBlank,
               let telURL = URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })") {
                Button {
                    openURL(telURL)
                } label: {
                    Image(systemName: "phone.fill")
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ClientEditorView: View {
    @State private var name: String
    @State private var phone: String
    @State private var email: String
    @State private var note: String
    @State private var contactId: String?
    @State private var photoPath: String?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isShowingContactPicker = false

    let existingClient: ClientItem?
    let onSave: (ClientItem) async -> Void
    let onDelete: () async -> Void
    let onCancel: () -> Void

    init(
        initial: ClientItem?,
        onSave: @escaping (ClientItem) async -> Void,
        onDelete: @escaping () async -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.existingClient = initial
        _name = State(initialValue: initial?.name ?? "")
        _phone = State(initialValue: initial?.phone ?? "")
        _email = State(initialValue: initial?.email ?? "")
        _note = State(initialValue: initial?.note ?? "")
        _contactId = State(initialValue: initial?.contactId)
        _photoPath = State(initialValue: initial?.photoPath)
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
                                .fill(Color.accentColor.opacity(0.16))
                                .frame(width: 56, height: 56)
                                .overlay {
                                    Image(systemName: "person.fill")
                                        .font(.title2)
                                        .foregroundStyle(.tint)
                                }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                                Text("common.choose_photo")
                                    .font(.subheadline.weight(.medium))
                            }
                            Button("contacts.import_from_contacts") {
                                isShowingContactPicker = true
                            }
                            .font(.subheadline)
                        }
                    }

                    TextField("clients.name_placeholder", text: $name)
                    TextField("clients.phone_placeholder", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("clients.email_placeholder", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }

                Section("editor.notes") {
                    TextField("editor.note_placeholder", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                if existingClient != nil {
                    Section {
                        Button("clients.delete_button", role: .destructive) {
                            Task { await onDelete() }
                        }
                    }
                }
            }
            .navigationTitle(
                existingClient == nil
                    ? LocalizedStringKey("clients.new_title")
                    : LocalizedStringKey("clients.edit_title")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.save") {
                        guard let trimmed = name.nilIfBlank else { return }
                        let item = ClientItem(
                            id: existingClient?.id ?? 0,
                            name: trimmed,
                            phone: phone.nilIfBlank,
                            email: email.nilIfBlank,
                            contactId: contactId,
                            photoPath: photoPath,
                            note: note.nilIfBlank
                        )
                        Task { await onSave(item) }
                    }
                    .disabled(name.nilIfBlank == nil)
                }
            }
            .sheet(isPresented: $isShowingContactPicker) {
                ContactPickerSheet { info in
                    if name.nilIfBlank == nil { name = info.fullName }
                    if let p = info.phone { phone = p }
                    if let e = info.email { email = e }
                    contactId = info.identifier
                    if let data = info.imageData, let saved = try? MediaStorageService.saveImageData(data, prefix: "client") {
                        photoPath = saved
                    }
                    isShowingContactPicker = false
                } onCancel: {
                    isShowingContactPicker = false
                }
            }
            .onChange(of: pickedPhoto) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let saved = try? MediaStorageService.saveImageData(data, prefix: "client") {
                        photoPath = saved
                    }
                }
            }
        }
    }
}
