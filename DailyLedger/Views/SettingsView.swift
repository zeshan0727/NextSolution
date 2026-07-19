import SwiftUI
import UniformTypeIdentifiers

private struct SettingsNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct SettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var selectedCurrency = "QAR"
    @State private var exportingBackup = false
    @State private var exportingCSV = false
    @State private var importing = false
    @State private var confirmingDelete = false
    @State private var notice: SettingsNotice?

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
                    Text("Changing currency updates how amounts are displayed. It does not convert existing values.")
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
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete All Transactions", systemImage: "trash.fill")
                    }
                    .disabled(store.transactions.isEmpty)
                } header: {
                    Label("Data", systemImage: "lock.shield.fill")
                } footer: {
                    Text("Your ledger is stored only on this iPhone unless you export it. Create a backup before deleting the app.")
                }

                Section {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Minimum iOS", value: "16.0")
                    LabeledContent("Storage", value: "Offline")
                } header: {
                    Label("About", systemImage: "info.circle.fill")
                }
            }
            .navigationTitle("Settings")
            .onAppear { selectedCurrency = store.currencyCode }
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
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.json, .commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                importFile(result)
            }
            .confirmationDialog(
                "Delete all transactions?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) {
                    store.deleteAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone unless you have exported a backup.")
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
            settings: store.settings
        ))
    }

    private var csvDocument: CSVDocument {
        CSVDocument(data: ImportExportCodec.csvData(
            transactions: store.transactions,
            currencyCode: store.currencyCode
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

    private func importFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let count = try store.importFile(at: url)
            notice = SettingsNotice(
                title: "Import Complete",
                message: count == 1 ? "1 new transaction was added." : "\(count) new transactions were added."
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

