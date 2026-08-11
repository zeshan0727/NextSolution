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
    @State private var openAISaveStatus = ""
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

                                Button {
                                    saveOpenAIKey()
                                } label: {
                                    Label("Save OpenAI API Key", systemImage: "checkmark.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                if !openAISaveStatus.isEmpty {
                                    Text(openAISaveStatus)
                                        .font(.caption)
                                        .foregroundStyle(openAIConnected ? AppTheme.green : AppTheme.red)
                                }
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
                        LabeledContent("Version", value: "1.3.70")
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
                if openAIConnected && openAISaveStatus.isEmpty {
                    openAISaveStatus = "Connected · SMS AI automatically uses this saved OpenAI key."
                }
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
        let value = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            openAIConnected = OpenAIService.shared.hasAPIKey
            openAISaveStatus = "Enter or paste an OpenAI API key first."
            return
        }

        do {
            try OpenAIService.shared.saveAPIKey(value)
            let verified = OpenAIService.shared.loadAPIKey() == value && OpenAIService.shared.hasAPIKey
            openAIConnected = verified
            if verified {
                openAIAPIKey = ""
                openAISaveStatus = "Saved & Connected · SMS AI will use this OpenAI key automatically."
                notice = SettingsNotice(
                    title: "OpenAI Connected",
                    message: "The API key was saved and verified. Automatic SMS database AI recovery is now linked to this same OpenAI connection."
                )
                Task {
                    await SMSOpenAIAutoRecoveryCoordinator.shared.processPending()
                }
            } else {
                openAISaveStatus = "Save failed verification."
                notice = SettingsNotice(title: "Save Failed", message: "Next Ledger could not read the OpenAI key back after saving.")
            }
        } catch {
            openAIConnected = OpenAIService.shared.hasAPIKey
            openAISaveStatus = "Save failed: \(error.localizedDescription)"
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

    @State private var reveal = false
    @State private var pasteStatus = ""
    @State private var focusRequest = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            UIKitAPIKeyTextField(
                text: $apiKey,
                placeholder: connected ? "Enter replacement API key" : "OpenAI API key",
                isSecure: !reveal,
                focusRequest: focusRequest
            )
            .frame(height: 44)

            HStack(spacing: 10) {
                Button {
                    if let value = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !value.isEmpty {
                        apiKey = value
                        pasteStatus = "API key pasted. Tap Save OpenAI API Key below."
                        focusRequest += 1
                    } else {
                        pasteStatus = "Clipboard is empty. Copy your OpenAI API key first."
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)

                Button {
                    focusRequest += 1
                } label: {
                    Label("Tap to Edit", systemImage: "keyboard")
                }
                .buttonStyle(.bordered)

                Button {
                    reveal.toggle()
                    focusRequest += 1
                } label: {
                    Label(reveal ? "Hide" : "Show", systemImage: reveal ? "eye.slash" : "eye")
                }
                .buttonStyle(.bordered)

                if !apiKey.isEmpty {
                    Button(role: .destructive) {
                        apiKey = ""
                        pasteStatus = ""
                        focusRequest += 1
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.caption)

            Text(pasteStatus.isEmpty
                 ? (connected
                    ? "OpenAI key saved. Tap the field to replace it, or use Paste."
                    : "Tap directly inside the field for the keyboard, or use Paste from clipboard.")
                 : pasteStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct UIKitAPIKeyTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isSecure: Bool
    let focusRequest: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField(frame: .zero)
        field.borderStyle = .roundedRect
        field.placeholder = placeholder
        field.isSecureTextEntry = isSecure
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.keyboardType = .asciiCapable
        field.textContentType = .password
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .done
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        if field.text != text { field.text = text }
        field.placeholder = placeholder
        if field.isSecureTextEntry != isSecure {
            let wasFirstResponder = field.isFirstResponder
            field.isSecureTextEntry = isSecure
            if wasFirstResponder {
                field.becomeFirstResponder()
            }
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                field.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var lastFocusRequest = 0

        init(text: Binding<String>) {
            _text = text
        }

        @objc func changed(_ sender: UITextField) {
            text = sender.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
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
