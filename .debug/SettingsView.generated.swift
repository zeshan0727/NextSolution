import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct SettingsNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum ImportSource {
    case files
    case googleDrive
}

struct SettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @StateObject private var backupSync = BackupSyncService.shared
    @AppStorage("DailyLedgerICloudSync") private var iCloudSyncEnabled = false
    @State private var selectedCurrency = "QAR"
    @State private var exportingBackup = false
    @State private var exportingCSV = false
    @State private var showingImporter = false
    @State private var importSource = ImportSource.files
    @State private var exportingGoogleDrive = false
    @State private var notice: SettingsNotice?
    @State private var deepSeekAPIKey = ""
    @State private var deepSeekConnected = DeepSeekService.shared.hasAPIKey
    @State private var testingDeepSeek = false
    @State private var openAIAPIKey = ""
    @State private var openAIConnected = OpenAIService.shared.hasAPIKey
    @State private var testingOpenAI = false
    @AppStorage("OpenAIModel") private var openAIModel = "gpt-4.1-nano"
    @AppStorage("DeepSeekModel") private var deepSeekModel = "deepseek-v4-flash"
    @AppStorage("DailyLedgerAppearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage("DailyLedgerVisualTheme") private var visualTheme = AppVisualTheme.glass.rawValue
    @State private var showingSMSStatus = true
    @AppStorage("AccountingPeriodStartDay") private var accountingPeriodStartDay = 26
    @AppStorage("AccountingPeriodLockEnabled") private var accountingPeriodLockEnabled = false
    @AppStorage("AccountingPeriodLockThroughTimestamp") private var accountingPeriodLockThroughTimestamp = 0.0

    private let currencies = ["QAR", "USD", "GBP", "EUR", "AED", "SAR", "PKR", "INR"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SettingsSectionPage(title: "Display") {
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
                        }
                    } label: {
                        Label("Display", systemImage: "circle.lefthalf.filled")
                    }
                }

                Section {
                    NavigationLink {
                        SettingsSectionPage(title: "Accounting Period") {
                        Stepper(value: $accountingPeriodStartDay, in: 1...28) {
                            HStack {
                                Text("Period Start Day")
                                Spacer()
                                Text(ordinalDay(accountingPeriodStartDay))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        LabeledContent("Default Cycle", value: accountingPeriodLabel)
                        Divider()
                        Toggle("Enable Period Lock", isOn: accountingPeriodLockBinding)
                        if accountingPeriodLockEnabled {
                            DatePicker(
                                "Lock Through Date",
                                selection: accountingPeriodLockDateBinding,
                                displayedComponents: .date
                            )
                            Label(
                                "Transactions on or before this date are protected",
                                systemImage: "lock.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        }
                    } label: {
                        Label("Accounting Period", systemImage: "calendar.badge.clock")
                    }
                }

                Section {
                    NavigationLink {
                        SettingsSectionPage(title: "Import & Export") {
                        Button {
                            exportingCSV = true
                        } label: {
                            SettingsRow(
                                title: "Export CSV",
                                subtitle: "",
                                icon: "tablecells.fill",
                                color: AppTheme.green
                            )
                        }

                        Button {
                            exportingBackup = true
                        } label: {
                            SettingsRow(
                                title: "Export JSON Backup",
                                subtitle: "",
                                icon: "externaldrive.fill",
                                color: AppTheme.blue
                            )
                        }

                        Button {
                            importSource = .files
                            showingImporter = true
                        } label: {
                            SettingsRow(
                                title: "Import Data",
                                subtitle: "",
                                icon: "square.and.arrow.down.fill",
                                color: AppTheme.orange
                            )
                        }
                        }
                    } label: {
                        Label("Import & Export", systemImage: "arrow.left.arrow.right")
                    }
                }

                Section {
                    NavigationLink {
                        SettingsSectionPage(title: "Backup & Sync") {
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
                            importSource = .googleDrive
                            showingImporter = true
                        } label: {
                            Label("Restore from Google Drive", systemImage: "arrow.down.doc.fill")
                        }
                        LabeledContent("Last Backup") {
                            Text(backupSync.lastBackupDate?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                        }
                        Text(backupSync.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    } label: {
                        Label("Backup & Sync", systemImage: "icloud.fill")
                    }
                }

                Section {
                    NavigationLink {
                        SettingsSectionPage(title: "AI") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label(
                                        deepSeekConnected ? "DeepSeek Connected" : "DeepSeek Not Connected",
                                        systemImage: deepSeekConnected ? "checkmark.shield.fill" : "shield.slash.fill"
                                    )
                                    .foregroundStyle(deepSeekConnected ? AppTheme.green : .secondary)
                                    Spacer()
                                    if testingDeepSeek { ProgressView() }
                                }

                                SecureField(
                                    deepSeekConnected ? "Enter a replacement DeepSeek key" : "DeepSeek API key",
                                    text: $deepSeekAPIKey
                                )
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                                Picker("DeepSeek Model", selection: $deepSeekModel) {
                                    Text("V4 Flash · Faster").tag("deepseek-v4-flash")
                                    Text("V4 Pro · Deeper").tag("deepseek-v4-pro")
                                }

                                LabeledContent("Local Ledger Search", value: "Enabled")

                                Button("Save DeepSeek API Key") { saveDeepSeekKey() }
                                    .disabled(deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Button("Test DeepSeek Connection") { testDeepSeekConnection() }
                                    .disabled(!deepSeekConnected || testingDeepSeek)
                                if deepSeekConnected {
                                    Button("Disconnect DeepSeek", role: .destructive) {
                                        DeepSeekService.shared.deleteAPIKey()
                                        deepSeekAPIKey = ""
                                        deepSeekConnected = false
                                    }
                                }
                            }
                            .padding(.vertical, 6)

                            Divider()

                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label(
                                        openAIConnected ? "OpenAI Connected" : "OpenAI Not Connected",
                                        systemImage: openAIConnected ? "checkmark.shield.fill" : "shield.slash.fill"
                                    )
                                    .foregroundStyle(openAIConnected ? AppTheme.green : .secondary)
                                    Spacer()
                                    if testingOpenAI { ProgressView() }
                                }
                                OpenAIAPIKeyEntryView(apiKey: $openAIAPIKey, connected: openAIConnected)
                                Picker("OpenAI Text Model", selection: $openAIModel) {
                                    ForEach(OpenAIService.selectableModels, id: \.self) { model in
                                        Text(modelLabel(model)).tag(model)
                                    }
                                }

                                Button("Save OpenAI API Key", action: saveOpenAIKey)
                                    .disabled(openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Button("Test OpenAI Connection", action: testOpenAIConnection)
                                    .disabled(!openAIConnected || testingOpenAI)
                                if openAIConnected {
                                    Button("Disconnect OpenAI", role: .destructive) {
                                        OpenAIService.shared.deleteAPIKey()
                                        openAIConnected = false
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    } label: {
                        Label("AI", systemImage: "brain.head.profile")
                    }
                }

                Section {
                    NavigationLink {
                        SettingsSectionPage(title: "Shortcuts") {
                        SettingsRow(
                            title: "Add Expense",
                            subtitle: "",
                            icon: "minus.circle.fill",
                            color: AppTheme.red
                        )
                        SettingsRow(
                            title: "Add Income",
                            subtitle: "",
                            icon: "plus.circle.fill",
                            color: AppTheme.green
                        )
                        Link(destination: URL(string: "shortcuts://")!) {
                            SettingsRow(
                                title: "Open Shortcuts App",
                                subtitle: "",
                                icon: "square.stack.3d.up.fill",
                                color: AppTheme.purple
                            )
                        }
                        }
                    } label: {
                        Label("Shortcuts", systemImage: "wand.and.stars")
                    }
                }

                Section {
                    NavigationLink {
                        SettingsSectionPage(title: "Automatic Bank SMS") {
                        NavigationLink {
                            SMSImportConsoleView()
                        } label: {
                            SettingsRow(
                                title: "SMS Import Console",
                                subtitle: "",
                                icon: "terminal.fill",
                                color: AppTheme.orange
                            )
                        }
                        }
                    } label: {
                        Label("Automatic Bank SMS", systemImage: "message.badge.filled.fill")
                    }
                }

                Section {
                    NavigationLink {
                        SettingsSectionPage(title: "Vendor Rules") {
                        NavigationLink {
                            VendorRulesView()
                        } label: {
                            SettingsRow(
                                title: "Vendor Category Rules",
                                subtitle: "",
                                icon: "tag.fill",
                                color: AppTheme.purple
                            )
                        }
                        }
                    } label: {
                        Label("Vendor Rules", systemImage: "tag.fill")
                    }
                }

                Section {
                    NavigationLink {
                        SettingsSectionPage(title: "Planning & Categorization") {
                        NavigationLink {
                            BudgetSettingsView()
                        } label: {
                            SettingsRow(
                                title: "Budgets",
                                subtitle: "",
                                icon: "target",
                                color: AppTheme.green
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
                                subtitle: "",
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
                                subtitle: "",
                                icon: "checklist",
                                color: AppTheme.blue
                            )
                        }
                        .disabled(store.uncategorizedTransactions.isEmpty)
                        }
                    } label: {
                        Label("Planning & Categorization", systemImage: "target")
                    }
                }

                Section {
                    NavigationLink {
                        SettingsSectionPage(title: "About") {
                        LabeledContent("Version", value: "1.3.54")
                        LabeledContent("Author", value: "Next Solution – Zeeshan Barvi")
                        }
                    } label: {
                        Label("About", systemImage: "info.circle.fill")
                    }
                }

}
            .navigationTitle("Settings")
            .onAppear {
                selectedCurrency = store.currencyCode
                openAIConnected = OpenAIService.shared.hasAPIKey
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

    private var accountingPeriodLockBinding: Binding<Bool> {
        Binding(
            get: { accountingPeriodLockEnabled },
            set: { enabled in
                accountingPeriodLockEnabled = enabled
                if enabled && accountingPeriodLockThroughTimestamp <= 0 {
                    accountingPeriodLockThroughTimestamp = Calendar.current
                        .startOfDay(for: Date())
                        .timeIntervalSince1970
                }
            }
        )
    }

    private var accountingPeriodLockDateBinding: Binding<Date> {
        Binding(
            get: {
                guard accountingPeriodLockThroughTimestamp > 0 else {
                    return Calendar.current.startOfDay(for: Date())
                }
                return Date(timeIntervalSince1970: accountingPeriodLockThroughTimestamp)
            },
            set: { date in
                accountingPeriodLockThroughTimestamp = Calendar.current
                    .startOfDay(for: date)
                    .timeIntervalSince1970
            }
        )
    }

    private var accountingPeriodLabel: String {
        if accountingPeriodStartDay == 1 {
            return "1st → Month End"
        }
        return "\(ordinalDay(accountingPeriodStartDay)) → \(ordinalDay(accountingPeriodStartDay - 1))"
    }

    private func ordinalDay(_ day: Int) -> String {
        let suffix: String
        switch day % 100 {
        case 11, 12, 13:
            suffix = "th"
        default:
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix)"
    }

    private func currencyLabel(_ code: String) -> String {
        let names: [String: String] = [
            "QAR": "Qatari Riyal", "USD": "US Dollar", "GBP": "British Pound",
            "EUR": "Euro", "AED": "UAE Dirham", "SAR": "Saudi Riyal",
            "PKR": "Pakistani Rupee", "INR": "Indian Rupee"
        ]
        return "\(code) – \(names[code] ?? code)"
    }

    private func modelLabel(_ model: String) -> String {
        switch model {
        case "gpt-5-nano": return "GPT-5 Nano · Lowest-cost GPT-5"
        case "gpt-5-mini": return "GPT-5 Mini · Balanced"
        case "gpt-5.6-sol": return "GPT-5.6 Sol · Frontier"
        default: return model
        }
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
                    model: deepSeekModel,
                    maxTokens: 20
                )
                await MainActor.run {
                    testingDeepSeek = false
                    notice = SettingsNotice(title: "Connection Successful", message: "Next Ledger can reach DeepSeek.")
                }
            } catch {
                await MainActor.run {
                    testingDeepSeek = false
                    notice = SettingsNotice(title: "Connection Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func saveOpenAIKey() {
        do {
            try OpenAIService.shared.saveAPIKey(openAIAPIKey)
            openAIAPIKey = ""
            openAIConnected = OpenAIService.shared.hasAPIKey
            notice = SettingsNotice(title: "OpenAI Connected", message: "The API key was saved securely in this iPhone's Keychain.")
        } catch {
            notice = SettingsNotice(title: "Connection Failed", message: error.localizedDescription)
        }
    }

    private func testOpenAIConnection() {
        testingOpenAI = true
        Task {
            do {
                _ = try await OpenAIService.shared.request(
                    messages: [OpenAIMessage(role: "user", content: "Reply with exactly: Connected")],
                    model: openAIModel, maxTokens: 20
                )
                await MainActor.run {
                    testingOpenAI = false
                    notice = SettingsNotice(title: "Connection Successful", message: "Next Ledger can reach OpenAI.")
                }
            } catch {
                await MainActor.run {
                    testingOpenAI = false
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
                title: source == .googleDrive ? "Restore Complete" : "Import Complete",
                message: "Added \(transactionText) and \(accountText)."
            )
        } catch {
            notice = SettingsNotice(
                title: source == .googleDrive ? "Restore Failed" : "Import Failed",
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

private struct SettingsSectionPage<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        List {
            Section {
                content
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OpenAIAPIKeyEntryView: View {
    @Binding var apiKey: String
    let connected: Bool

    @State private var showOpenAIKey = false
    @State private var pasteStatus = ""
    @FocusState private var openAIKeyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if showOpenAIKey {
                    TextField(connected ? "Enter replacement API key" : "OpenAI API key", text: $apiKey)
                        .focused($openAIKeyFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .textContentType(.password)
                        .submitLabel(.done)
                        .onSubmit { openAIKeyFocused = false }
                } else {
                    SecureField(connected ? "Enter replacement API key" : "OpenAI API key", text: $apiKey)
                        .focused($openAIKeyFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .textContentType(.password)
                        .submitLabel(.done)
                        .onSubmit { openAIKeyFocused = false }
                }

                Button {
                    showOpenAIKey.toggle()
                    openAIKeyFocused = true
                } label: {
                    Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showOpenAIKey ? "Hide API key" : "Show API key")
            }

            HStack(spacing: 10) {
                Button {
                    if let value = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !value.isEmpty {
                        apiKey = value
                        pasteStatus = "API key pasted. Tap Save OpenAI API Key below."
                        openAIKeyFocused = true
                    } else {
                        pasteStatus = "Clipboard is empty. Copy the OpenAI API key first."
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)

                Button {
                    openAIKeyFocused = true
                } label: {
                    Label("Tap to Edit", systemImage: "keyboard")
                }
                .buttonStyle(.bordered)

                if !apiKey.isEmpty {
                    Button(role: .destructive) {
                        apiKey = ""
                        pasteStatus = ""
                        openAIKeyFocused = true
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.caption)

            Text(pasteStatus.isEmpty
                 ? (connected
                    ? "OpenAI key saved. Paste a new key only to replace it."
                    : "Tap the field or Tap to Edit for the keyboard, or copy the key and tap Paste.")
                 : pasteStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}
