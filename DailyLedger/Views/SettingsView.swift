import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct SettingsNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum ImportSource {
    case importFile
    case restoreBackup
}

struct SettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @StateObject private var backupSync = BackupSyncService.shared
    @AppStorage("DailyLedgerICloudSync") private var iCloudSyncEnabled = false
    @State private var selectedCurrency = "QAR"
    @State private var exportingBackup = false
    @State private var exportingCSV = false
    @State private var showingImporter = false
    @State private var importSource = ImportSource.importFile
    @State private var exportingFilesBackup = false
    @State private var notice: SettingsNotice?
    @AppStorage("DailyLedgerAppearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage("DailyLedgerVisualTheme") private var visualTheme = AppVisualTheme.glass.rawValue

    private let currencies = ["QAR", "USD", "GBP", "EUR", "AED", "SAR", "PKR", "INR"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Reporting Currency", selection: $selectedCurrency) {
                        ForEach(currencies, id: \.self) { code in
                            Text(currencyLabel(code)).tag(code)
                        }
                    }
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.rawValue).tag(option.rawValue)
                        }
                    }
                    Picker("App Theme", selection: $visualTheme) {
                        ForEach(AppVisualTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme.rawValue)
                        }
                    }
                } header: {
                    Label("Display", systemImage: "circle.lefthalf.filled")
                } footer: {
                    Text("Reporting Currency controls Home and Reports totals. Account balances remain in each account's own currency.")
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
                            subtitle: "Complete Next Ledger backup",
                            icon: "externaldrive.fill",
                            color: AppTheme.blue
                        )
                    }

                    Button {
                        importSource = .importFile
                        showingImporter = true
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
                        exportingFilesBackup = true
                    } label: {
                        Label("Back Up to Files", systemImage: "folder.fill.badge.plus")
                    }
                    Button {
                        importSource = .restoreBackup
                        showingImporter = true
                    } label: {
                        Label("Restore from Files", systemImage: "folder.fill.badge.arrow.down")
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
                    Text("iCloud backup uses your private iCloud Drive container. File backups use Apple's system file picker and only access locations you choose.")
                }

                Section {
                    SettingsRow(
                        title: "Add Expense",
                        subtitle: "Save an expense from Shortcuts",
                        icon: "minus.circle.fill",
                        color: AppTheme.red
                    )
                    SettingsRow(
                        title: "Add Income",
                        subtitle: "Save income from Shortcuts",
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
                    Text("Next Ledger exposes supported actions to Apple's Shortcuts app for user-initiated data entry.")
                }

                Section {
                    NavigationLink {
                        BudgetSettingsView()
                    } label: {
                        SettingsRow(
                            title: "Budgets",
                            subtitle: "Category limits, progress and alerts",
                            icon: "target",
                            color: AppTheme.green
                        )
                    }

                    NavigationLink {
                        VendorRulesView()
                    } label: {
                        SettingsRow(
                            title: "Vendor Category Rules",
                            subtitle: "Match vendor names to categories",
                            icon: "tag.fill",
                            color: AppTheme.purple
                        )
                    }

                    Button {
                        let summary = store.automaticallyCategorizeTransactions()
                        notice = SettingsNotice(
                            title: "Categorization Complete",
                            message: "Categorized \(summary.categorizedCount) transactions. \(summary.reviewCount) still need your review."
                        )
                    } label: {
                        SettingsRow(
                            title: "Auto-Categorize Transactions",
                            subtitle: "Apply your local vendor rules to recent transactions",
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
                            subtitle: "\(store.uncategorizedTransactions.count) recent transactions remaining",
                            icon: "checklist",
                            color: AppTheme.blue
                        )
                    }
                    .disabled(store.uncategorizedTransactions.isEmpty)
                } header: {
                    Label("Planning & Categorization", systemImage: "target")
                } footer: {
                    Text("Categorization runs locally using the rules saved in Next Ledger.")
                }

                Section {
                    Link(destination: URL(string: "https://nextsolution.cc/next-ledger-privacy/")!) {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }
                    Link(destination: URL(string: "https://nextsolution.cc/next-ledger-support/")!) {
                        Label("Support Website", systemImage: "safari.fill")
                    }
                } header: {
                    Label("Privacy & Support", systemImage: "lock.shield.fill")
                } footer: {
                    Text("Your ledger records stay under your control. Review the Privacy Policy for details about local storage, exports, and optional iCloud backup.")
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Author", value: "Next Solution – Zeeshan Barvi")
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
                defaultFilename: "NextLedger-Backup"
            ) { result in
                showExportResult(result, format: "backup")
            }
            .fileExporter(
                isPresented: $exportingCSV,
                document: csvDocument,
                contentType: .commaSeparatedText,
                defaultFilename: "NextLedger-Transactions"
            ) { result in
                showExportResult(result, format: "CSV file")
            }
            .fileExporter(
                isPresented: $exportingFilesBackup,
                document: backupDocument,
                contentType: .json,
                defaultFilename: "NextLedger-Backup"
            ) { result in
                showExportResult(result, format: "backup file")
            }
            .sheet(isPresented: $showingImporter) {
                ImportDocumentPicker { result in
                    showingImporter = false
                    importFile(result, source: importSource)
                }
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

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
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

    private func showExportResult(_ result: Result<URL, Error>, format: String) {
        switch result {
        case .success:
            notice = SettingsNotice(title: "Export Complete", message: "Your \(format) is ready.")
        case .failure(let error):
            notice = SettingsNotice(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func importFile(_ result: Result<URL, Error>, source: ImportSource) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try coordinatedData(from: url)
            let summary = try store.importData(data)
            let transactionText = summary.transactionCount == 1
                ? "1 transaction"
                : "\(summary.transactionCount) transactions"
            let accountText = summary.accountCount == 1
                ? "1 account"
                : "\(summary.accountCount) accounts"
            notice = SettingsNotice(
                title: source == .restoreBackup ? "Restore Complete" : "Import Complete",
                message: "Added \(transactionText) and \(accountText)."
            )
        } catch {
            notice = SettingsNotice(
                title: source == .restoreBackup ? "Restore Failed" : "Import Failed",
                message: error.localizedDescription
            )
        }
    }

    private func coordinatedData(from url: URL) throws -> Data {
        var coordinatorError: NSError?
        var readResult: Result<Data, Error>?
        NSFileCoordinator().coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinatorError
        ) { coordinatedURL in
            readResult = Result {
                try Data(contentsOf: coordinatedURL, options: .mappedIfSafe)
            }
        }
        if let coordinatorError { throw coordinatorError }
        guard let readResult else {
            throw CocoaError(.fileReadUnknown)
        }
        return try readResult.get()
    }
}

private struct ImportDocumentPicker: UIViewControllerRepresentable {
    let completion: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.json, .commaSeparatedText, .plainText, .data, .item],
            asCopy: true
        )
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (Result<URL, Error>) -> Void

        init(completion: @escaping (Result<URL, Error>) -> Void) {
            self.completion = completion
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard let url = urls.first else {
                completion(.failure(CocoaError(.fileReadNoSuchFile)))
                return
            }
            completion(.success(url))
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
