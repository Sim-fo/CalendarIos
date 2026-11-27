import SwiftUI
import UniformTypeIdentifiers

struct BackupView: View {
    private let backupService: BackupService

    @State private var summary: BackupSummary?
    @State private var exportDocument: JSONBackupDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var pendingImportData: Data?
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    init(database: AppDatabase) {
        self.backupService = BackupService(dbWriter: database.dbWriter)
    }

    var body: some View {
        Form {
            Section {
                Text("backup.json_description")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await prepareExport() }
                } label: {
                    Label("backup.export_json", systemImage: "square.and.arrow.up")
                }

                Button {
                    isImporting = true
                } label: {
                    Label("backup.import_json", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("backup.section.local")
            }

            if let summary {
                Section("backup.section.summary") {
                    summaryRow("backup.count.events", value: summary.eventCount)
                    summaryRow("feature.templates.title", value: summary.templateCount)
                    summaryRow("feature.todo.title", value: summary.todoCount)
                    summaryRow("feature.trackers.title", value: summary.trackerCount)
                    summaryRow("feature.birthdays.title", value: summary.birthdayCount)
                    summaryRow("feature.weekly_events.title", value: summary.weeklyRecurringCount)
                    summaryRow("feature.clients.title", value: summary.clientCount)
                    summaryRow("feature.map_markers.title", value: summary.locationCount)
                }
            }

            Section("backup.section.icloud") {
                HStack(spacing: 12) {
                    Image(systemName: "icloud")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("backup.icloud_title")
                            .font(.subheadline.weight(.semibold))
                        Text("backup.icloud_subtitle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("feature.backup.title")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSummary()
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument ?? JSONBackupDocument(),
            contentType: .json,
            defaultFilename: defaultBackupFilename()
        ) { result in
            switch result {
            case .success:
                statusMessage = String(localized: "backup.export_success")
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    pendingImportData = try Data(contentsOf: url)
                } catch {
                    errorMessage = error.localizedDescription
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert(
            "backup.restore_confirm_title",
            isPresented: Binding(
                get: { pendingImportData != nil },
                set: { if !$0 { pendingImportData = nil } }
            )
        ) {
            Button("backup.restore_button", role: .destructive) {
                guard let data = pendingImportData else { return }
                pendingImportData = nil
                Task { await performImport(data) }
            }
            Button("common.cancel", role: .cancel) {
                pendingImportData = nil
            }
        } message: {
            Text("backup.restore_confirm_message")
        }
        .alert(
            "common.error_title",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("common.ok") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func summaryRow(_ titleKey: LocalizedStringKey, value: Int) -> some View {
        HStack {
            Text(titleKey)
            Spacer()
            Text("\(value)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func loadSummary() async {
        summary = try? await backupService.fetchSummary()
    }

    private func prepareExport() async {
        do {
            let data = try await backupService.exportJSONData()
            exportDocument = JSONBackupDocument(data: data)
            isExporting = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performImport(_ data: Data) async {
        do {
            try await backupService.importJSONData(data)
            statusMessage = String(localized: "backup.import_success")
            await loadSummary()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func defaultBackupFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return "CalendarIos_Backup_\(formatter.string(from: Date()))"
    }
}
