import SwiftUI

struct EventCreateView: View {
    let selectedDate: Date
    let templates: [EventTypeWithCount]
    let lastSelectedTypeId: Int64?
    let calendar: Calendar
    let use24hFormat: Bool
    let onSelectTemplate: (EventType) -> Void
    let onDeleteTemplate: (EventTypeWithCount, Bool) -> Void
    let onCreateTemplate: () -> Void
    let onCreateUnique: () -> Void
    let onCancel: () -> Void

    @State private var templatePendingDelete: EventTypeWithCount?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text(CalendarDateFormatter.time(for: selectedDate, calendar: calendar, use24h: use24hFormat))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .accessibilityIdentifier("weekly.eventCreateTime")

                    Text(CalendarDateFormatter.longDate(for: selectedDate, calendar: calendar))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)
                .padding(.bottom, 16)

                if templates.isEmpty {
                    ContentUnavailableView(
                        "event_create.empty_title",
                        systemImage: "square.stack.3d.up",
                        description: Text("event_create.empty_hint")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(templates) { item in
                            Button {
                                onSelectTemplate(item.eventType)
                            } label: {
                                TemplateListRow(
                                    item: item,
                                    isHighlighted: item.id == lastSelectedTypeId
                                )
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

                HStack(spacing: 12) {
                    Button(action: onCreateTemplate) {
                        Text("event_create.create_template")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)

                    Button(action: onCreateUnique) {
                        Text("event_create.unique_event")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("weekly.eventCreateUniqueButton")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(uiColor: .systemBackground))
                .overlay(alignment: .top) {
                    Divider()
                }
            }
            .background(CalendarColor.groupedBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel", action: onCancel)
                }
            }
            .alert(
                (templatePendingDelete?.eventCount ?? 0) > 0
                    ? "templates.delete_with_events_title"
                    : "templates.delete_title",
                isPresented: Binding(
                    get: { templatePendingDelete != nil },
                    set: { if !$0 { templatePendingDelete = nil } }
                ),
                presenting: templatePendingDelete
            ) { item in
                if item.eventCount > 0 {
                    Button("templates.delete_with_events", role: .destructive) {
                        onDeleteTemplate(item, true)
                    }
                    Button("templates.delete_keep_events") {
                        onDeleteTemplate(item, false)
                    }
                } else {
                    Button("common.delete", role: .destructive) {
                        onDeleteTemplate(item, false)
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
        }
    }
}
