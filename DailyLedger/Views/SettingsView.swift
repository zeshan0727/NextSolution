import SwiftUI
import UniformTypeIdentifiers

private struct SettingsNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct SettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @StateObject private var backupSync = BackupSyncService.shared
    @AppStorage("DailyLedgerICloudSync") private var iCloudSyncEnabled = false
    @State private var selectedCurrency = "QAR"
    @State private var exportingBackup = false
    @State private var exportingCSV = false
    @State private var importing = false
    @State private var exportingGoogleDrive = false
    @State private var importingGoogleDrive = false
    @State private var notice: SettingsNotice?
    @State private var deepSeekAPIKey = ""
    @State private var deepSeekConnected = DeepSeekService.shared.hasAPIKey
    @State private var testingDeepSeek = false
    @AppStorage("DeepSeekModel") private var deepSeekModel = "deepseek-v4-flash"

    private let currencies = ["QAR", "USD", "GBP", "EUR", "AED", "SAR", "PKR", "INR"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Currency", selection: $selectedCurrency) {
                        ForEach(currencies, id: \.self) { code in
                            Text(currencyLabel(code)).tag(code)
                        }
                    }
                } header: {
                    Label("General", systemImage: "slider.horizontal.3")
                } footer: {
                    Text("This chooses the currency shown on Home and Reports. Each account keeps its own currency and amounts are never converted automatically.")
                }

                Section {
                    Button {
                        exportingCSV = true
                    } label: {
                        SettingsRow(
                            title: "Export CSV",
                            subtitle: "Use with Excel, Numbers, or other apps",
                            icon: "tablecells.fill",
                            color: AppTheme.green
                        )
                    }

                    Button {
                        exportingBackup = true
                    } label: {
                        SettingsRow(
                            title: "Export JSON Backup",
                            subtitle: "Complete Daily Ledger backup",
                            icon: "externaldrive.fill",
                            color: AppTheme.blue
                        )
                    }

                    Button {
                        importing = true
                    } label: {
                        SettingsRow(
                            title: "Import Data",
                            subtitle: "Merge a CSV or JSON file",
                            icon: "square.and.arrow.down.fill",
                            color: AppTheme.orange
                        )
                    }
                } header: {
                    Label("Import & Export", systemImage: "arrow.left.arrow.right")
                } footer: {
                    Text("Imported records are merged by their unique ID, helping prevent duplicate entries.")
                }

                Section {
                    Toggle("iCloud Drive Sync", isOn: $iCloudSyncEnabled)
                    Button {
                        store.syncBackupNow()
                    } label: {
                        Label("Back Up Now", systemImage: "icloud.and.arrow.up.fill")
                    }
                    Button {
                        store.restoreLatestICloudBackup()
                    } label: {
                        Label("Restore Latest iCloud Backup", systemImage: "icloud.and.arrow.down.fill")
                    }
                    Button {
                        exportingGoogleDrive = true
                    } label: {
                        Label("Back Up to Google Drive", systemImage: "externaldrive.badge.icloud")
                    }
                    Button {
                        importingGoogleDrive = true
                    } label: {
                        Label("Restore from Google Drive", systemImage: "arrow.down.doc.fill")
                    }
                    LabeledContent("Last Backup") {
                        Text(backupSync.lastBackupDate?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                    }
                    Text(backupSync.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Label("Backup & Sync", systemImage: "icloud.fill")
                } footer: {
                    Text("For Google Drive, install its app and enable Google Drive in Files. Choose Google Drive when the save or restore picker opens. iOS requires you to approve each Drive file operation.")
                }

                Section {
                    HStack {
                        Label(
                            deepSeekConnected ? "Connected" : "Not Connected",
                            systemImage: deepSeekConnected ? "checkmark.shield.fill" : "shield.slash.fill"
                        )
                        .foregroundStyle(deepSeekConnected ? AppTheme.green : .secondary)
                        Spacer()
                        if testingDeepSeek { ProgressView() }
                    }

                    SecureField(
                        deepSeekConnected ? "Enter a replacement API key" : "DeepSeek API key",
                        text: $deepSeekAPIKey
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Picker("Model", selection: $deepSeekModel) {
                        Text("V4 Flash · Faster").tag("deepseek-v4-flash")
                        Text("V4 Pro · Deeper").tag("deepseek-v4-pro")
                    }

                    Button("Save API Key") {
                        saveDeepSeekKey()
                    }
                    .disabled(deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Test DeepSeek Connection") {
                        testDeepSeekConnection()
                    }
                    .disabled(!deepSeekConnected || testingDeepSeek)

                    if deepSeekConnected {
                        Button("Disconnect DeepSeek", role: .destructive) {
                            DeepSeekService.shared.deleteAPIKey()
                            deepSeekAPIKey = ""
                            deepSeekConnected = false
                        }
                    }
                } header: {
                    Label("DeepSeek AI", systemImage: "sparkles")
                } footer: {
                    Text("The key is stored only in this iPhone's Keychain and is excluded from exports and backups. AI requests send summarized totals and categories, not raw SMS messages or account numbers.")
                }

                Section {
                    SettingsRow(
                        title: "Add Expense",
                        subtitle: "Save an expense without opening the app",
                        icon: "minus.circle.fill",
                        color: AppTheme.red
                    )
                    SettingsRow(
                        title: "Add Income",
                        subtitle: "Save income without opening the app",
                        icon: "plus.circle.fill",
                        color: AppTheme.green
                    )
                    Link(destination: URL(string: "shortcuts://")!) {
                        SettingsRow(
                            title: "Open Shortcuts App",
                            subtitle: "Build personal automations",
                            icon: "square.stack.3d.up.fill",
                            color: AppTheme.purple
                        )
                    }
                } header: {
                    Label("Shortcuts", systemImage: "wand.and.stars")
                } footer: {
                    Text("In Shortcuts, search for Daily Ledger actions. You can pass an amount, category, description, and date from another action.")
                }

                Section {
                    NavigationLink {
                        SMSImportPreferencesView()
                    } label: {
                        SettingsRow(
                            title: "SMS Import Preferences",
                            subtitle: "Match text, destination account, and status",
                            icon: "message.fill",
                            color: AppTheme.teal
                        )
                    }

                    NavigationLink {
                        VendorRulesView()
                    } label: {
                        SettingsRow(
                            title: "Vendor Category Rules",
                            subtitle: "Match vendor words to categories",
                            icon: "tag.fill",
                            color: AppTheme.purple
                        )
                    }
                } header: {
                    Label("Bank SMS", systemImage: "bolt.shield.fill")
                } footer: {
                    Text("Requires the Daily Ledger SMS Import package on RootHide Bootstrap 2.0 or later. Messages stay on this iPhone.")
                }

                Section {
                    Button {
                        let summary = store.automaticallyCategorizeTransactions()
                        notice = SettingsNotice(
                            title: "Categorization Complete",
                            message: "Categorized \(summary.categorizedCount) transactions. \(summary.reviewCount) still need your review."
                        )
                    } label: {
                        SettingsRow(
                            title: "Auto-Categorize Transactions",
                            subtitle: "Z-iP-14PM-16.0 transactions from the last 30 days",
                            icon: "wand.and.stars.inverse",
                            color: AppTheme.orange
                        )
                    }
                    .disabled(store.uncategorizedTransactions.isEmpty)

                    NavigationLink {
                        UncategorizedReviewView()
                    } label: {
                        SettingsRow(
                            title: "Review Uncategorized",
                            subtitle: "\(store.uncategorizedTransactions.count) recent Z-iP transactions remaining",
                            icon: "checklist",
                            color: AppTheme.blue
                        )
                    }
                    .disabled(store.uncategorizedTransactions.isEmpty)

                } header: {
                    Label("Data", systemImage: "lock.shield.fill")
                } footer: {
                    Text("Your ledger is stored only on this iPhone unless you export it. Create a backup before deleting the app.")
                }

                Section {
                LabeledContent("Version", value: "1.3.14")
                    LabeledContent("Minimum iOS", value: "16.0")
                    LabeledContent("Storage", value: "Offline")
                } header: {
                    Label("About", systemImage: "info.circle.fill")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                selectedCurrency = store.currencyCode
            }
            .onChange(of: selectedCurrency) { store.updateCurrency($0) }
            .fileExporter(
                isPresented: $exportingBackup,
                document: backupDocument,
                contentType: .json,
                defaultFilename: "DailyLedger-Backup"
            ) { result in
                showExportResult(result, format: "backup")
            }
            .fileExporter(
                isPresented: $exportingCSV,
                document: csvDocument,
                contentType: .commaSeparatedText,
                defaultFilename: "DailyLedger-Transactions"
            ) { result in
                showExportResult(result, format: "CSV file")
            }
            .fileExporter(
                isPresented: $exportingGoogleDrive,
                document: backupDocument,
                contentType: .json,
                defaultFilename: "DailyLedger-GoogleDrive-Backup"
            ) { result in
                showExportResult(result, format: "Google Drive backup")
            }
            .fileImporter(
                isPresented: $importing,
                // Some Files providers report JSON/CSV downloads as a generic item.
                // Accepting UTType.item keeps those files selectable; the codec still
                // validates their actual bytes before importing anything.
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                importFile(result)
            }
            .fileImporter(
                isPresented: $importingGoogleDrive,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                importFile(result)
            }
            .alert(item: $notice) { notice in
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var backupDocument: BackupDocument {
        BackupDocument(data: ImportExportCodec.backupData(
            transactions: store.transactions,
            accounts: store.accounts,
            settings: store.settings
        ))
    }

    private var csvDocument: CSVDocument {
        CSVDocument(data: ImportExportCodec.csvData(
            transactions: store.transactions,
            accounts: store.accounts
        ))
    }

    private func currencyLabel(_ code: String) -> String {
        let names: [String: String] = [
            "QAR": "Qatari Riyal", "USD": "US Dollar", "GBP": "British Pound",
            "EUR": "Euro", "AED": "UAE Dirham", "SAR": "Saudi Riyal",
            "PKR": "Pakistani Rupee", "INR": "Indian Rupee"
        ]
        return "\(code) – \(names[code] ?? code)"
    }

    private func saveDeepSeekKey() {
        do {
            try DeepSeekService.shared.saveAPIKey(deepSeekAPIKey)
            deepSeekAPIKey = ""
            deepSeekConnected = true
            notice = SettingsNotice(title: "DeepSeek Connected", message: "The API key was saved securely in this iPhone's Keychain.")
        } catch {
            notice = SettingsNotice(title: "Connection Failed", message: error.localizedDescription)
        }
    }

    private func testDeepSeekConnection() {
        testingDeepSeek = true
        Task {
            do {
                _ = try await DeepSeekService.shared.request(
                    messages: [DeepSeekMessage(role: "user", content: "Reply with exactly: Connected")],
                    model: deepSeekModel
                )
                await MainActor.run {
                    testingDeepSeek = false
                    notice = SettingsNotice(title: "Connection Successful", message: "Daily Ledger can reach DeepSeek.")
                }
            } catch {
                await MainActor.run {
                    testingDeepSeek = false
                    notice = SettingsNotice(title: "Connection Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func showExportResult(_ result: Result<URL, Error>, format: String) {
        switch result {
        case .success:
            notice = SettingsNotice(title: "Export Complete", message: "Your \(format) is ready.")
        case .failure(let error):
            notice = SettingsNotice(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let summary = try store.importFile(at: url)
            let transactionText = summary.transactionCount == 1
                ? "1 transaction"
                : "\(summary.transactionCount) transactions"
            let accountText = summary.accountCount == 1
                ? "1 account"
                : "\(summary.accountCount) accounts"
            notice = SettingsNotice(
                title: "Import Complete",
                message: "Added \(transactionText) and \(accountText)."
            )
        } catch {
            notice = SettingsNotice(title: "Import Failed", message: error.localizedDescription)
        }
    }
}

private struct SettingsRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
