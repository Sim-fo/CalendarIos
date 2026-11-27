import SwiftUI

enum TodoFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case done

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .all: return "todo.filter.all"
        case .active: return "todo.filter.active"
        case .done: return "todo.filter.done"
        }
    }
}

@MainActor
final class TodoListViewModel: ObservableObject {
    @Published private(set) var items: [TodoItem] = []
    @Published var filter: TodoFilter = .all
    @Published var quickText: String = ""
    @Published var errorMessage: String?

    private let repository: any TodoRepository

    init(repository: any TodoRepository) {
        self.repository = repository
    }

    var filteredItems: [TodoItem] {
        switch filter {
        case .all: return items
        case .active: return items.filter { !$0.isDone }
        case .done: return items.filter { $0.isDone }
        }
    }

    func load() async {
        do {
            items = try await repository.fetchTodos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addQuickItem() async {
        guard let trimmed = quickText.nilIfBlank else { return }
        quickText = ""
        await save(id: nil, text: trimmed, isDone: false)
    }

    func save(id: Int64?, text: String, isDone: Bool) async {
        guard let trimmed = text.nilIfBlank else { return }
        do {
            _ = try await repository.upsertTodo(id: id, text: trimmed, isDone: isDone)
            items = try await repository.fetchTodos()
            NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggle(_ item: TodoItem) async {
        await save(id: item.id, text: item.text, isDone: !item.isDone)
    }

    func delete(_ item: TodoItem) async {
        do {
            try await repository.deleteTodo(id: item.id)
            items = try await repository.fetchTodos()
            NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TodoListView: View {
    @StateObject private var viewModel: TodoListViewModel
    @State private var editingItem: TodoItem?
    @State private var isCreatingSheetPresented = false

    init(repository: any TodoRepository) {
        _viewModel = StateObject(wrappedValue: TodoListViewModel(repository: repository))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("todo.filter.label", selection: $viewModel.filter) {
                ForEach(TodoFilter.allCases) { mode in
                    Text(mode.titleKey).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            HStack(spacing: 8) {
                TextField("todo.quick_add_placeholder", text: $viewModel.quickText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit {
                        Task { await viewModel.addQuickItem() }
                    }

                Button {
                    Task { await viewModel.addQuickItem() }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .disabled(viewModel.quickText.nilIfBlank == nil)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if viewModel.filteredItems.isEmpty {
                ContentUnavailableView(
                    "todo.empty.title",
                    systemImage: "checklist",
                    description: Text("todo.empty.subtitle")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.filteredItems) { item in
                        HStack(spacing: 12) {
                            Button {
                                Task { await viewModel.toggle(item) }
                            } label: {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(item.isDone ? Color.green : Color.secondary)
                            }
                            .buttonStyle(.plain)

                            Button {
                                editingItem = item
                            } label: {
                                Text(item.text)
                                    .strikethrough(item.isDone)
                                    .foregroundStyle(item.isDone ? .secondary : .primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
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
        .background(CalendarColor.groupedBackground)
        .navigationTitle("feature.todo.title")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCreatingSheetPresented = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editingItem) { item in
            TodoEditorSheet(initialText: item.text, isNew: false) { text in
                Task {
                    await viewModel.save(id: item.id, text: text, isDone: item.isDone)
                    editingItem = nil
                }
            } onCancel: {
                editingItem = nil
            }
        }
        .sheet(isPresented: $isCreatingSheetPresented) {
            TodoEditorSheet(initialText: "", isNew: true) { text in
                Task {
                    await viewModel.save(id: nil, text: text, isDone: false)
                    isCreatingSheetPresented = false
                }
            } onCancel: {
                isCreatingSheetPresented = false
            }
        }
        .task {
            await viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .calendarDataDidChange)) { _ in
            Task { await viewModel.load() }
        }
    }
}

private struct TodoEditorSheet: View {
    @State private var text: String
    let isNew: Bool
    let onSave: (String) -> Void
    let onCancel: () -> Void

    init(initialText: String, isNew: Bool, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _text = State(initialValue: initialText)
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("todo.text_placeholder", text: $text, axis: .vertical)
                    .lineLimit(3...8)
            }
            .navigationTitle(isNew ? LocalizedStringKey("todo.new_title") : LocalizedStringKey("todo.edit_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.save") {
                        onSave(text)
                    }
                    .disabled(text.nilIfBlank == nil)
                }
            }
        }
    }
}
