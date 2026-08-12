from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one match, found {count}: {old[:180]!r}")
    write(path, text.replace(old, new, 1))


# ---------------------------------------------------------------------------
# Version: app 1.3.76 / build 84. Daemon stays unchanged.
# ---------------------------------------------------------------------------
replace_once("project.yml", 'MARKETING_VERSION: "1.3.75"', 'MARKETING_VERSION: "1.3.76"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "83"', 'CURRENT_PROJECT_VERSION: "84"')

settings_path = "DailyLedger/Views/SettingsView.swift"
settings = read(settings_path)
settings = settings.replace(
    'LabeledContent("Version", value: "1.3.75")',
    'LabeledContent("Version", value: "1.3.76")',
    1,
)
write(settings_path, settings)


# ---------------------------------------------------------------------------
# Latest-15 review storage: Clear must really clear the fetched review records,
# dispositions, and SMS AI display/cache state. It must NOT delete Messages.app
# content, drafts, accounts, or ledger transactions.
# ---------------------------------------------------------------------------
review_path = "DailyLedger/Views/SMSLatest15ReviewView.swift"
review = read(review_path)

service_anchor = '''    static func setDisposition(_ value: String?, for id: UUID) {
        let key = "SMSLatest15Disposition.\\(id.uuidString)"
        if let value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }
'''
service_new = service_anchor + r'''

    @discardableResult
    static func clearFetchedReview() -> Int {
        let current = load()
        let defaults = UserDefaults.standard
        let keys = Array(defaults.dictionaryRepresentation().keys)
        for key in keys where key.hasPrefix("SMSLatest15Disposition.") {
            defaults.removeObject(forKey: key)
        }
        try? FileManager.default.removeItem(at: reviewURL)
        return current.count
    }
'''
if review.count(service_anchor) != 1:
    raise RuntimeError("SMSLatest15ReviewService setDisposition anchor missing")
review = review.replace(service_anchor, service_new, 1)

old_clear_button = '''                        Button(role: .destructive) {
                            clearAIResults(showNotice: true, clearSharedCache: true)
                        } label: {
                            Label("Clear SMS AI Results", systemImage: "trash.fill")
                        }
                        .buttonStyle(.bordered)
'''
new_clear_button = '''                        Button(role: .destructive) {
                            clearFetchedSMS()
                        } label: {
                            Label("Clear Fetched SMS", systemImage: "trash.fill")
                        }
                        .buttonStyle(.bordered)
'''
if review.count(old_clear_button) != 1:
    raise RuntimeError("SMS review clear button anchor missing")
review = review.replace(old_clear_button, new_clear_button, 1)

clear_anchor = '''    private func clearAIResults(showNotice: Bool, clearSharedCache: Bool) {
'''
clear_fetched = r'''    private func clearFetchedSMS() {
        let removed = SMSLatest15ReviewService.clearFetchedReview()
        SMSAIRecognitionService.clearAllCachedResults()
        clearAIResults(showNotice: false, clearSharedCache: false)
        reload()
        notice = removed > 0
            ? "Cleared \(removed) fetched SMS review record\(removed == 1 ? "" : "s") and their AI results. Messages on the iPhone, drafts, and ledger transactions were not deleted."
            : "No fetched SMS review records were stored. SMS AI results were cleared."
    }

'''
if clear_anchor not in review:
    raise RuntimeError("SMS review clearAIResults anchor missing")
review = review.replace(clear_anchor, clear_fetched + clear_anchor, 1)
write(review_path, review)


# ---------------------------------------------------------------------------
# SMS Import Console cleanup:
# - Account Mapping is a separate screen.
# - Fetch has a visible stored-result count and completion/error feedback.
# - Clear removes fetched review records + SMS AI results, not just AI cache.
# ---------------------------------------------------------------------------
console_path = "DailyLedger/Views/SMSImportConsoleView.swift"
console = read(console_path)

state_anchor = '''    @State private var draftCount = 0
'''
state_new = '''    @State private var draftCount = 0
    @State private var reviewCount = 0
'''
if console.count(state_anchor) != 1:
    raise RuntimeError("SMS console draftCount state anchor missing")
console = console.replace(state_anchor, state_new, 1)

mapping_block = '''                accountPicker(
                    title: "Credit Card **6760",
                    selection: cardBinding("6760"),
                    suggestedWords: ["credit", "6760"]
                )
                accountPicker(
                    title: "Debit Card **0023",
                    selection: cardBinding("0023"),
                    suggestedWords: ["debit", "0023"]
                )
                accountPicker(
                    title: "Current Account xxx364001",
                    selection: cardBinding("364001"),
                    suggestedWords: ["364001", "current", "cbq"]
                )
                accountPicker(
                    title: "Cash Account",
                    selection: optionalBinding(
                        get: { configuration.cashAccountID },
                        set: { configuration.cashAccountID = $0 }
                    ),
                    suggestedWords: ["cash"]
                )
                TextField("Custom card/account ending", text: customEndingBinding)
                    .keyboardType(.numberPad)
                accountPicker(
                    title: "Custom Account",
                    selection: optionalBinding(
                        get: { configuration.customAccountID },
                        set: { configuration.customAccountID = $0 }
                    ),
                    suggestedWords: []
                )

                TextField("Approved senders, comma separated", text: $approvedSendersText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

'''
mapping_link = '''                NavigationLink {
                    SMSAccountMappingView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.blue)
                            .frame(width: 38, height: 38)
                            .background(AppTheme.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Account Mapping")
                                .font(.body.weight(.semibold))
                            Text("Cards, current account, cash and approved senders")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

'''
if console.count(mapping_block) != 1:
    raise RuntimeError("SMS console account mapping controls block missing")
console = console.replace(mapping_block, mapping_link, 1)

console = console.replace(
    'Label(effectiveManualScanActive ? "Collecting Latest 15…" : "Collect Latest 15 Messages", systemImage: "arrow.clockwise.circle.fill")',
    'Label(effectiveManualScanActive ? "Fetching Latest SMS…" : "Fetch Latest 15 SMS", systemImage: "arrow.clockwise.circle.fill")',
    1,
)

review_link_old = '''                NavigationLink {
                    SMSLatest15ReviewView()
                } label: {
                    Label("Review Latest 15 Messages (\\(SMSLatest15ReviewService.load().count))", systemImage: "text.bubble.fill")
                }
'''
review_link_new = '''                NavigationLink {
                    SMSLatest15ReviewView()
                } label: {
                    HStack {
                        Label("Review Fetched SMS", systemImage: "text.bubble.fill")
                        Spacer()
                        Text("\\(reviewCount)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(reviewCount == 0)

                if reviewCount == 0 && !effectiveManualScanActive {
                    Text("No fetched SMS are stored. Tap Fetch Latest 15 SMS to load a fresh review list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
'''
if console.count(review_link_old) != 1:
    raise RuntimeError("SMS console review navigation anchor missing")
console = console.replace(review_link_old, review_link_new, 1)

console = console.replace(
    'Label("Clear AI Helper Results", systemImage: "trash.fill")',
    'Label("Clear Fetched SMS & AI", systemImage: "trash.fill")',
    1,
)
console = console.replace(
    '''                    Text("AI can analyze only the latest 10 pending review messages by default. Use Load 10 More inside Latest 15 Review when you want to expose more messages to AI.")
''',
    '''                    Text("AI starts with the latest 10 pending review messages. Clearing here removes the fetched review list and SMS AI results only; it does not delete phone messages or ledger data.")
''',
    1,
)

console = console.replace(
    'Label("Account Mapping", systemImage: "arrow.triangle.branch")',
    'Label("SMS Import & Review", systemImage: "message.fill")',
    1,
)

onappear_old = '''            configuration = SMSImportConsoleService.loadConfiguration()
            applySuggestedMappings()
            loadingConfiguration = false
'''
onappear_new = '''            configuration = SMSImportConsoleService.loadConfiguration()
            approvedSendersText = configuration.approvedSenders.joined(separator: ", ")
            applySuggestedMappings()
            loadingConfiguration = false
'''
if console.count(onappear_old) != 1:
    raise RuntimeError("SMS console onAppear configuration anchor missing")
console = console.replace(onappear_old, onappear_new, 1)

refresh_old = '''        snapshot = SMSImportConsoleService.loadSnapshot()
        installerDiagnostic = SMSImportConsoleService.loadInstallerDiagnostic()
        draftCount = SMSImportConsoleService.loadDrafts().count

        if localManualScan,
           snapshot.scanInProgress != true,
           let requested = manualScanRequestedAt,
           let completed = snapshot.lastScanDate,
           completed >= requested.addingTimeInterval(-1) {
            localManualScan = false
        }
        if localManualScan,
           let requested = manualScanRequestedAt,
           Date().timeIntervalSince(requested) > 45 {
            localManualScan = false
        }
'''
refresh_new = '''        snapshot = SMSImportConsoleService.loadSnapshot()
        installerDiagnostic = SMSImportConsoleService.loadInstallerDiagnostic()
        draftCount = SMSImportConsoleService.loadDrafts().count
        reviewCount = SMSLatest15ReviewService.load().count

        if localManualScan,
           snapshot.scanInProgress != true,
           let requested = manualScanRequestedAt,
           let completed = snapshot.lastScanDate,
           completed >= requested.addingTimeInterval(-1) {
            localManualScan = false
            reviewCount = SMSLatest15ReviewService.load().count
            notice = reviewCount > 0
                ? "Fetched \\(reviewCount) SMS for review. Open Review Fetched SMS to inspect them."
                : "The fetch completed, but no SMS review records were returned. Check Messages database access and Installer Diagnostics."
        }
        if localManualScan,
           let requested = manualScanRequestedAt,
           Date().timeIntervalSince(requested) > 45 {
            localManualScan = false
            notice = "The SMS fetch did not complete. Check Daemon status and Installer Diagnostics, then try again."
        }
'''
if console.count(refresh_old) != 1:
    raise RuntimeError("SMS console refresh block missing")
console = console.replace(refresh_old, refresh_new, 1)

clear_old = '''    private func clearSMSAIHelperResults() {
        SMSAIRecognitionService.clearAllCachedResults()
        aiProcessedCount = 0
        notice = "SMS AI Helper results were cleared. Latest 15 messages, drafts, review decisions, and ledger transactions were left unchanged."
        refresh()
    }
'''
clear_new = '''    private func clearSMSAIHelperResults() {
        let removed = SMSLatest15ReviewService.clearFetchedReview()
        SMSAIRecognitionService.clearAllCachedResults()
        aiProcessedCount = 0
        reviewCount = 0
        notice = removed > 0
            ? "Cleared \\(removed) fetched SMS review record\\(removed == 1 ? "" : "s") and SMS AI results. Messages on the iPhone, drafts, accounts, and ledger transactions were not deleted."
            : "No fetched SMS review records were stored. SMS AI results were cleared."
        refresh()
    }
'''
if console.count(clear_old) != 1:
    raise RuntimeError("SMS console clear helper function missing")
console = console.replace(clear_old, clear_new, 1)

# Add a separate account-mapping screen before logs.
logs_anchor = '''private struct SMSImportLogsView: View {
'''
account_mapping_view = r'''private struct SMSAccountMappingView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var configuration = SMSImportConfiguration()
    @State private var approvedSendersText = "Cb SMS"
    @State private var loading = true
    @State private var savedStatus = ""

    var body: some View {
        List {
            Section {
                mappingPicker("Credit Card **6760", selection: cardBinding("6760"))
                mappingPicker("Debit Card **0023", selection: cardBinding("0023"))
                mappingPicker("Current Account xxx364001", selection: cardBinding("364001"))
                mappingPicker(
                    "Cash Account",
                    selection: optionalBinding(
                        get: { configuration.cashAccountID },
                        set: { configuration.cashAccountID = $0 }
                    )
                )
            } header: {
                Label("Known Accounts", systemImage: "creditcard.and.123")
            } footer: {
                Text("Choose the ledger account that belongs to each bank/card ending. These mappings are used when SMS drafts are prepared.")
            }

            Section {
                TextField("Custom card/account ending", text: customEndingBinding)
                    .keyboardType(.numberPad)
                mappingPicker(
                    "Custom Account",
                    selection: optionalBinding(
                        get: { configuration.customAccountID },
                        set: { configuration.customAccountID = $0 }
                    )
                )
            } header: {
                Label("Custom Mapping", systemImage: "plus.rectangle.on.rectangle")
            }

            Section {
                TextField("Approved senders, comma separated", text: $approvedSendersText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Only SMS from these sender names are considered for the automatic bank-SMS pipeline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Approved Senders", systemImage: "person.crop.circle.badge.checkmark")
            }

            Section {
                Button {
                    persist(showStatus: true)
                    dismiss()
                } label: {
                    Label("Save Account Mapping", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderedProminent)

                if !savedStatus.isEmpty {
                    Text(savedStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Account Mapping")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loading = true
            configuration = SMSImportConsoleService.loadConfiguration()
            approvedSendersText = configuration.approvedSenders.joined(separator: ", ")
            applySuggestedMappings()
            loading = false
        }
        .onChange(of: configuration) { _ in
            guard !loading else { return }
            persist(showStatus: false)
        }
        .onChange(of: approvedSendersText) { _ in
            guard !loading else { return }
            persist(showStatus: false)
        }
    }

    private var activeAccounts: [LedgerAccount] {
        store.activeAccounts.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    @ViewBuilder
    private func mappingPicker(_ title: String, selection: Binding<String?>) -> some View {
        Picker(title, selection: selection) {
            Text("Not Set").tag(String?.none)
            ForEach(activeAccounts) { account in
                Text("\(account.name) · \(account.currencyCode)")
                    .tag(Optional(account.id.uuidString))
            }
        }
    }

    private func cardBinding(_ ending: String) -> Binding<String?> {
        optionalBinding(
            get: { configuration.cardAccountIDs[ending] },
            set: { value in
                if let value {
                    configuration.cardAccountIDs[ending] = value
                } else {
                    configuration.cardAccountIDs.removeValue(forKey: ending)
                }
            }
        )
    }

    private func optionalBinding(
        get: @escaping () -> String?,
        set: @escaping (String?) -> Void
    ) -> Binding<String?> {
        Binding(get: get, set: set)
    }

    private var customEndingBinding: Binding<String> {
        Binding(
            get: { configuration.customEnding },
            set: { value in
                configuration.customEnding = String(value.filter(\.isNumber).suffix(8))
            }
        )
    }

    private func applySuggestedMappings() {
        if configuration.cardAccountIDs["6760"] == nil,
           let account = suggestedAccount(words: ["credit", "6760"]) {
            configuration.cardAccountIDs["6760"] = account.id.uuidString
        }
        if configuration.cardAccountIDs["0023"] == nil,
           let account = suggestedAccount(words: ["debit", "0023"]) {
            configuration.cardAccountIDs["0023"] = account.id.uuidString
        }
        if configuration.cardAccountIDs["364001"] == nil,
           let account = suggestedAccount(words: ["364001", "current", "cbq"]) {
            configuration.cardAccountIDs["364001"] = account.id.uuidString
        }
        if configuration.cashAccountID == nil,
           let account = suggestedAccount(words: ["cash"]) {
            configuration.cashAccountID = account.id.uuidString
        }
    }

    private func suggestedAccount(words: [String]) -> LedgerAccount? {
        activeAccounts.first { account in
            let name = account.name.lowercased()
            return words.contains { name.contains($0) }
        }
    }

    private func persist(showStatus: Bool) {
        configuration.approvedSenders = approvedSendersText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if configuration.approvedSenders.isEmpty {
            configuration.approvedSenders = ["Cb SMS"]
        }
        do {
            try SMSImportConsoleService.saveConfiguration(configuration)
            if showStatus { savedStatus = "Saved" }
        } catch {
            if showStatus { savedStatus = "Could not save: \(error.localizedDescription)" }
        }
    }
}

'''
if logs_anchor not in console:
    raise RuntimeError("SMS Import Logs anchor missing")
if "private struct SMSAccountMappingView" in console:
    raise RuntimeError("SMSAccountMappingView already exists")
console = console.replace(logs_anchor, account_mapping_view + logs_anchor, 1)
write(console_path, console)

print("Prepared Next Ledger 1.3.76: SMS Clear now removes fetched review records + AI results, Fetch shows result/error feedback, and Account Mapping moved to a separate screen.")
