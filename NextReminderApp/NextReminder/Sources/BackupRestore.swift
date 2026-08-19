import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let nextReminderBackup = UTType(exportedAs: "com.nextsolution.nextreminder.backup")
}

struct NextReminderBackupPackage: Codable {
    var formatVersion: Int
    var createdAt: Date
    var appVersion: String
    var reminders: [ReminderItem]
    var categories: [ReminderCategory]
    var settingsPropertyList: Data
}

struct NextReminderBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.nextReminderBackup, .json, .data]
    }

    var data: Data

    init(package: NextReminderBackupPackage) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        data = try encoder.encode(package)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BackupRestoreError.invalidBackup
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum BackupRestoreError: LocalizedError {
    case invalidBackup
    case unsupportedVersion
    case settingsEncoding
    case settingsDecoding

    var errorDescription: String? {
        switch self {
        case .invalidBackup:
            return "The selected file is not a valid Next Reminder backup."
        case .unsupportedVersion:
            return "This backup was created by an unsupported app version."
        case .settingsEncoding:
            return "The app settings could not be prepared for backup."
        case .settingsDecoding:
            return "The settings inside this backup could not be restored."
        }
    }
}

enum BackupCloudProvider: String, CaseIterable, Identifiable {
    case iCloud
    case googleDrive
    case dropbox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iCloud: return "iCloud Drive"
        case .googleDrive: return "Google Drive"
        case .dropbox: return "Dropbox"
        }
    }

    var symbol: String {
        switch self {
        case .iCloud: return "icloud.and.arrow.up.fill"
        case .googleDrive: return "externaldrive.connected.to.line.below.fill"
        case .dropbox: return "shippingbox.fill"
        }
    }

    var explanation: String {
        switch self {
        case .iCloud:
            return "Save or open the backup in your iCloud Drive folder."
        case .googleDrive:
            return "Choose Google Drive in the iOS Files picker."
        case .dropbox:
            return "Choose Dropbox in the iOS Files picker."
        }
    }
}

struct NextReminderBackupManager {
    private static let formatVersion = 1
    private static let transientKeys: Set<String> = [
        "NextReminder.PendingNotificationAction",
        "NextReminder.PendingEmailAutomationAction",
        "NextReminder.PendingAutomationAction",
        "NextReminder.GmailConnection.v1"
    ]

    static func createPackage(store: ReminderStore) throws -> NextReminderBackupPackage {
        let settings = try backupSettingsPropertyList()
        return NextReminderBackupPackage(
            formatVersion: formatVersion,
            createdAt: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            reminders: store.reminders,
            categories: store.categories,
            settingsPropertyList: settings
        )
    }

    @MainActor
    static func restore(
        package: NextReminderBackupPackage,
        reminderStore: ReminderStore,
        emailStore: EmailAutomationStore,
        automationStore: AutomationStore
    ) throws {
        guard package.formatVersion <= formatVersion else {
            throw BackupRestoreError.unsupportedVersion
        }

        let settings = try PropertyListSerialization.propertyList(
            from: package.settingsPropertyList,
            options: [],
            format: nil
        )
        guard let dictionary = settings as? [String: Any] else {
            throw BackupRestoreError.settingsDecoding
        }

        restoreSettings(dictionary)
        GmailConnectionStore.shared.invalidate()
        reminderStore.replaceAll(
            reminders: package.reminders,
            categories: package.categories
        )
        emailStore.reloadFromDisk()
        automationStore.objectWillChange.send()
        NotificationCenter.default.post(name: .nextReminderBackupRestored, object: nil)
    }

    private static func backupSettingsPropertyList() throws -> Data {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            throw BackupRestoreError.settingsEncoding
        }

        var domain = UserDefaults.standard.persistentDomain(forName: bundleID) ?? [:]
        for key in Array(domain.keys) where shouldExclude(key) {
            domain.removeValue(forKey: key)
        }

        // A remote Gmail connector may expire or belong to another device/server database.
        // Preserve the email templates and preferences, but require a fresh secure connection.
        if let data = domain[EmailAutomationSettings.defaultsKey] as? Data,
           var emailSettings = try? JSONDecoder().decode(EmailAutomationSettings.self, from: data) {
            emailSettings.remoteConnectorID = ""
            emailSettings.senderLabel = ""
            domain[EmailAutomationSettings.defaultsKey] = try? JSONEncoder().encode(emailSettings)
        }

        guard PropertyListSerialization.propertyList(domain, isValidFor: .binary) else {
            throw BackupRestoreError.settingsEncoding
        }
        return try PropertyListSerialization.data(
            fromPropertyList: domain,
            format: .binary,
            options: 0
        )
    }

    private static func restoreSettings(_ values: [String: Any]) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let defaults = UserDefaults.standard
        let existing = defaults.persistentDomain(forName: bundleID) ?? [:]

        for key in existing.keys where key.hasPrefix("NextReminder.") && !shouldExclude(key) {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in values where !shouldExclude(key) {
            defaults.set(value, forKey: key)
        }

        defaults.removeObject(forKey: "NextReminder.GmailConnection.v1")
        if var emailSettings = Optional(EmailAutomationSettings.load()) {
            emailSettings.remoteConnectorID = ""
            emailSettings.senderLabel = ""
            emailSettings.persist()
        }
    }

    private static func shouldExclude(_ key: String) -> Bool {
        transientKeys.contains(key)
            || key.localizedCaseInsensitiveContains("apikey")
            || key.localizedCaseInsensitiveContains("api-key")
            || key.localizedCaseInsensitiveContains("password")
            || key.localizedCaseInsensitiveContains("secret")
            || key.localizedCaseInsensitiveContains("token")
    }

    static func decodePackage(from data: Data) throws -> NextReminderBackupPackage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(NextReminderBackupPackage.self, from: data)
        } catch {
            throw BackupRestoreError.invalidBackup
        }
    }
}

extension Notification.Name {
    static let nextReminderBackupRestored = Notification.Name("NextReminder.BackupRestored")
}

struct BackupRestoreView: View {
    @EnvironmentObject private var reminderStore: ReminderStore
    @EnvironmentObject private var emailStore: EmailAutomationStore
    @EnvironmentObject private var automationStore: AutomationStore

    @State private var exportDocument: NextReminderBackupDocument?
    @State private var exportFileName = "Next-Reminder-Backup"
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var pendingPackage: NextReminderBackupPackage?
    @State private var selectedProvider: BackupCloudProvider = .iCloud
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var showRestoreConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                summaryCard
                backupSection
                restoreSection
                securitySection
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(Color.nextBackground.ignoresSafeArea())
        .navigationTitle("Backup & Restore")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .nextReminderBackup,
            defaultFilename: exportFileName
        ) { result in
            switch result {
            case .success:
                statusMessage = "Backup saved successfully."
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            exportDocument = nil
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.nextReminderBackup, .json, .data],
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        .confirmationDialog(
            "Restore this backup?",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace Current Data", role: .destructive) {
                restorePendingPackage()
            }
            Button("Cancel", role: .cancel) {
                pendingPackage = nil
            }
        } message: {
            if let package = pendingPackage {
                Text("This will replace the current reminders and app settings with \(package.reminders.count) reminders and \(package.categories.count) categories from \(package.createdAt.formatted(date: .abbreviated, time: .shortened)).")
            }
        }
        .alert("Backup & Restore", isPresented: Binding(
            get: { statusMessage != nil || errorMessage != nil },
            set: {
                if !$0 {
                    statusMessage = nil
                    errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                statusMessage = nil
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? statusMessage ?? "")
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.icloud.fill")
                .font(.title2)
                .foregroundStyle(.nextOrange)
                .frame(width: 52, height: 52)
                .background(Color.nextOrange.opacity(0.14), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 4) {
                Text("Portable App Backup")
                    .font(.headline)
                Text("\(reminderStore.reminders.count) reminders • \(reminderStore.categories.count) categories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(15)
        .nextCard()
    }

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Create Backup", trailing: "Choose cloud location")
            Text("Each button opens the iOS Files save picker. Select the matching cloud provider or any other folder you prefer.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(BackupCloudProvider.allCases) { provider in
                providerButton(provider, actionTitle: "Back Up") {
                    prepareExport(to: provider)
                }
            }
        }
    }

    private var restoreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Restore Backup", trailing: "Replaces current data")
            Text("Open a .nextreminderbackup file from iCloud Drive, Google Drive, Dropbox, or On My iPhone.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(BackupCloudProvider.allCases) { provider in
                providerButton(provider, actionTitle: "Restore") {
                    selectedProvider = provider
                    isImporting = true
                }
            }
        }
    }

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Included & Protected")
            Label("Reminders, categories, completed history, themes, templates, recipient shortcuts, and non-sensitive settings", systemImage: "checkmark.shield.fill")
                .foregroundStyle(.green)
            Label("Gmail, scheduler, and DeepSeek credentials are never included; reconnect them after restoring on another device", systemImage: "lock.shield.fill")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(14)
        .nextCard()
    }

    private func providerButton(
        _ provider: BackupCloudProvider,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: provider.symbol)
                    .font(.title3)
                    .foregroundStyle(.nextOrange)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(actionTitle) with \(provider.title)")
                        .font(.headline)
                    Text(provider.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .nextCard()
        }
        .buttonStyle(.plain)
    }

    private func prepareExport(to provider: BackupCloudProvider) {
        selectedProvider = provider
        do {
            let package = try NextReminderBackupManager.createPackage(store: reminderStore)
            exportDocument = try NextReminderBackupDocument(package: package)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmm"
            exportFileName = "Next-Reminder-Backup-\(formatter.string(from: package.createdAt))"
            isExporting = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                pendingPackage = try NextReminderBackupManager.decodePackage(from: data)
                showRestoreConfirmation = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restorePendingPackage() {
        guard let package = pendingPackage else { return }
        do {
            try NextReminderBackupManager.restore(
                package: package,
                reminderStore: reminderStore,
                emailStore: emailStore,
                automationStore: automationStore
            )
            pendingPackage = nil
            statusMessage = "Backup restored successfully. Reconnect Gmail and DeepSeek if needed."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
