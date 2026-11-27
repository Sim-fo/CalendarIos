import SwiftUI

@MainActor
final class MapMarkersViewModel: ObservableObject {
    @Published private(set) var links: [LocationLinkItem] = []
    @Published var searchQuery = ""
    @Published var errorMessage: String?

    private let repository: any LocationLinkRepository

    init(repository: any LocationLinkRepository) {
        self.repository = repository
    }

    var filteredLinks: [LocationLinkItem] {
        guard let q = searchQuery.nilIfBlank?.lowercased() else { return links }
        return links.filter {
            ($0.title?.lowercased().contains(q) ?? false) || $0.url.lowercased().contains(q)
        }
    }

    func load() async {
        do {
            links = try await repository.fetchLocationLinks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(id: Int64?, title: String?, url: String) async -> Bool {
        guard let trimmedURL = url.nilIfBlank else { return false }
        do {
            _ = try await repository.upsertLocationLink(id: id, url: trimmedURL, title: title?.nilIfBlank, type: nil)
            links = try await repository.fetchLocationLinks()
            NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ item: LocationLinkItem) async {
        do {
            try await repository.deleteLocationLink(id: item.id)
            links = try await repository.fetchLocationLinks()
            NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MapMarkersListView: View {
    @StateObject private var viewModel: MapMarkersViewModel
    @State private var editingLink: LocationLinkItem?
    @State private var isCreatingNew = false
    @Environment(\.openURL) private var openURL

    init(repository: any LocationLinkRepository) {
        _viewModel = StateObject(wrappedValue: MapMarkersViewModel(repository: repository))
    }

    var body: some View {
        Group {
            if viewModel.filteredLinks.isEmpty {
                ContentUnavailableView(
                    "map_markers.empty.title",
                    systemImage: "mappin.and.ellipse",
                    description: Text("map_markers.empty.subtitle")
                )
            } else {
                List {
                    ForEach(viewModel.filteredLinks) { link in
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.red)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(link.displayTitle)
                                    .font(.body.weight(.semibold))
                                Text(link.url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if let resolvedURL = resolvedExternalURL(from: link.url) {
                                Button {
                                    openURL(resolvedURL)
                                } label: {
                                    Image(systemName: "arrow.up.right.square")
                                        .foregroundStyle(.tint)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingLink = link
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await viewModel.delete(link) }
                            } label: {
                                Label("common.delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .searchable(text: $viewModel.searchQuery, prompt: Text("map_markers.search_prompt"))
        .navigationTitle("feature.map_markers.title")
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
            MapMarkerEditorSheet(initial: nil) { title, url in
                if await viewModel.save(id: nil, title: title, url: url) {
                    isCreatingNew = false
                }
            } onCancel: {
                isCreatingNew = false
            }
        }
        .sheet(item: $editingLink) { link in
            MapMarkerEditorSheet(initial: link) { title, url in
                if await viewModel.save(id: link.id, title: title, url: url) {
                    editingLink = nil
                }
            } onCancel: {
                editingLink = nil
            }
        }
        .task {
            await viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .calendarDataDidChange)) { _ in
            Task { await viewModel.load() }
        }
    }

    private func resolvedExternalURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = URL(string: trimmed), direct.scheme != nil {
            return direct
        }
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            return URL(string: "http://maps.apple.com/?q=\(encoded)")
        }
        return nil
    }
}

private struct MapMarkerEditorSheet: View {
    @State private var title: String
    @State private var url: String

    let isNew: Bool
    let onSave: (String?, String) async -> Void
    let onCancel: () -> Void

    init(
        initial: LocationLinkItem?,
        onSave: @escaping (String?, String) async -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.isNew = initial == nil
        _title = State(initialValue: initial?.title ?? "")
        _url = State(initialValue: initial?.url ?? "")
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("editor.basics") {
                    TextField("map_markers.title_placeholder", text: $title)
                    TextField("map_markers.url_placeholder", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(isNew ? LocalizedStringKey("map_markers.new_title") : LocalizedStringKey("map_markers.edit_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.save") {
                        Task { await onSave(title.nilIfBlank, url) }
                    }
                    .disabled(url.nilIfBlank == nil)
                }
            }
        }
    }
}
