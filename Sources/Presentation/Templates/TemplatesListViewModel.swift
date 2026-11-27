import Foundation

@MainActor
final class TemplatesListViewModel: ObservableObject {
    @Published private(set) var templates: [EventTypeWithCount] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let repository: any EventTypeRepository

    init(repository: any EventTypeRepository) {
        self.repository = repository
    }

    func load() async {
        isLoading = templates.isEmpty
        errorMessage = nil
        do {
            templates = try await repository.fetchEventTypesWithCounts()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func save(_ draft: EventTypeDraft) async -> EventType? {
        errorMessage = nil
        do {
            var resolvedDraft = draft
            let trimmed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                let existingNames = try await repository.fetchEventTypes().map(\.title)
                resolvedDraft.title = NameGenerator.generateNextName(existingNames: existingNames)
            } else {
                let isUnique = try await repository.isEventTypeTitleUnique(trimmed, excludingId: draft.id)
                guard isUnique else {
                    errorMessage = String(localized: "templates.error.duplicate_name")
                    return nil
                }
                resolvedDraft.title = trimmed
            }

            let saved = try await repository.upsertEventType(resolvedDraft)
            templates = try await repository.fetchEventTypesWithCounts()
            NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
            return saved
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func delete(_ item: EventTypeWithCount, deleteLinkedEvents: Bool) async {
        errorMessage = nil
        do {
            try await repository.deleteEventType(id: item.id, deleteLinkedEvents: deleteLinkedEvents)
            templates = try await repository.fetchEventTypesWithCounts()
            NotificationCenter.default.post(name: .calendarDataDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissError() {
        errorMessage = nil
    }
}
