protocol EventTypeRepository: Sendable {
    func fetchEventTypes() async throws -> [EventType]
}

