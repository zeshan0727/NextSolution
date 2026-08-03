from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    (ROOT / path).write_text(content, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match in {path}, found {count}: {old[:220]!r}")
    write(path, text.replace(old, new, 1))


# SMS daemon: manual scans inspect exactly the latest 30 incoming SMS rows.
source = "RootHideSMSQueue/Sources/main.m"
replace_once(
    source,
    'static NSString *const kDaemonVersion = @"2.1.2";',
    'static NSString *const kDaemonVersion = @"2.1.3";',
)
replace_once(
    source,
    '''    NSInteger approvedMessageLimit = manualRequested ? 250 : 10;
    NSInteger databaseRowLimit = manualRequested ? 2000 : 250;
''',
    '''    NSInteger approvedMessageLimit = manualRequested ? 30 : 10;
    NSInteger databaseRowLimit = manualRequested ? 30 : 250;
''',
)

# Restore rejected reviewed IDs while preserving IDs that already exist as ledger transactions.
service = "DailyLedger/Services/SMSImportConsoleService.swift"
replace_once(
    service,
    '''    private static func withDraftLock<T>(_ work: () throws -> T) throws -> T {
''',
    '''    static func restoreRejectedForReview(recordedTransactionIDs: Set<UUID>) throws -> Int {
        try withDraftLock {
            var reviewed: [String] = []
            if let data = try? Data(contentsOf: reviewedURL) {
                reviewed = (try? JSONDecoder().decode([String].self, from: data)) ?? []
            }
            let originalCount = reviewed.count
            reviewed.removeAll { value in
                guard let identifier = UUID(uuidString: value) else { return false }
                return !recordedTransactionIDs.contains(identifier)
            }
            try JSONEncoder().encode(reviewed).write(to: reviewedURL, options: .atomic)
            return originalCount - reviewed.count
        }
    }

    private static func withDraftLock<T>(_ work: () throws -> T) throws -> T {
''',
)

console = "DailyLedger/Views/SMSImportConsoleView.swift"
replace_once(
    console,
    '''                Text("Automatic scans recheck only the latest 10 approved-bank SMS. Manual recovery scans search up to 250 approved-bank SMS and reset the automatic timer.")
''',
    '''                Text("Automatic scans recheck the latest 10 approved-bank SMS. Manual Scan checks only the latest 30 incoming SMS rows, ignores already approved, rejected or pending IDs, and creates drafts only for unreported transactions.")
''',
)
replace_once(
    console,
    '''                Button {
                    saveConfiguration(requestScan: true)
                } label: {
                    Label("Find Unrecorded Recent SMS", systemImage: "arrow.clockwise.circle.fill")
                }
''',
    '''                Button {
                    saveConfiguration(requestScan: true)
                } label: {
                    Label("Manual Scan · Latest 30 SMS", systemImage: "arrow.clockwise.circle.fill")
                }

                Button {
                    restoreRejectedForReview()
                } label: {
                    Label("Restore Rejected SMS for Review", systemImage: "arrow.uturn.backward.circle.fill")
                }
''',
)
replace_once(
    console,
    '''    private func refresh() {
''',
    '''    private func restoreRejectedForReview() {
        do {
            let recordedIDs = Set(store.transactions.map(\\.id))
            let restored = try SMSImportConsoleService.restoreRejectedForReview(
                recordedTransactionIDs: recordedIDs
            )
            guard restored > 0 else {
                notice = "No rejected SMS IDs were found. Approved transactions and current drafts were left unchanged."
                return
            }
            configuration.scanRequestID += 1
            try SMSImportConsoleService.saveConfiguration(configuration)
            notice = "Restored \\(restored) rejected SMS item\\(restored == 1 ? \"\" : \"s\") for review. A latest-30 manual scan was requested."
            refresh()
        } catch {
            notice = "Rejected SMS could not be restored: \\(error.localizedDescription)"
        }
    }

    private func refresh() {
''',
)

# Compact DeepSeek and OpenAI controls into one expandable AI section.
settings = "DailyLedger/Views/SettingsView.swift"
replace_once(
    settings,
    '''    @State private var showingSMSStatus = true
''',
    '''    @State private var showingSMSStatus = true
    @State private var showingAISettings = false
''',
)

old_ai = '''                Section {
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

                    LabeledContent("Local Ledger Search", value: "Enabled")

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
                    Text("The key is stored in this iPhone's Keychain with a device-protected update fallback. It is excluded from exports and backups. Ledger Lookup searches locally and uses no API tokens.")
                }

                Section {
                    Label(openAIConnected ? "Connected" : "Not Connected",
                          systemImage: openAIConnected ? "checkmark.shield.fill" : "shield.slash.fill")
                        .foregroundStyle(openAIConnected ? AppTheme.green : .secondary)
                    SecureField(openAIConnected ? "Enter replacement API key" : "OpenAI API key", text: $openAIAPIKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("Text Model", selection: $openAIModel) {
                        ForEach(OpenAIService.selectableModels, id: \\.self) { model in
                            Text(modelLabel(model)).tag(model)
                        }
                    }
                    Button("Save OpenAI API Key", action: saveOpenAIKey)
                        .disabled(openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Test OpenAI Connection", action: testOpenAIConnection)
                        .disabled(!openAIConnected || testingOpenAI)
                    if testingOpenAI { ProgressView() }
                    if openAIConnected {
                        Button("Disconnect OpenAI", role: .destructive) {
                            OpenAIService.shared.deleteAPIKey()
                            openAIConnected = false
                        }
                    }
                } header: {
                    Label("OpenAI Chat", systemImage: "bubble.left.and.bubble.right.fill")
                } footer: {
                    Text("The key uses Keychain plus a device-protected update fallback and is excluded from exports. GPT-5 model availability depends on your API project. Next Ledger caps each answer to control tokens.")
                }
'''

new_ai = '''                Section {
                    DisclosureGroup(isExpanded: $showingAISettings) {
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

                            SecureField(
                                openAIConnected ? "Enter a replacement OpenAI key" : "OpenAI API key",
                                text: $openAIAPIKey
                            )
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                            Picker("OpenAI Text Model", selection: $openAIModel) {
                                ForEach(OpenAIService.selectableModels, id: \\.self) { model in
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
                    } label: {
                        Label("AI Settings", systemImage: "sparkles")
                            .font(.headline)
                    }
                } header: {
                    Label("AI", systemImage: "brain.head.profile")
                } footer: {
                    Text("Open this single section to manage DeepSeek and OpenAI. API keys remain in the iPhone Keychain and are excluded from backups and exports.")
                }
'''
replace_once(settings, old_ai, new_ai)

for path in ["RootHideSMSQueue/control"]:
    replace_once(path, "Version: 2.1.2", "Version: 2.1.3")
for path in ["RootHideSMSQueue/postinst", "RootHideSMSQueue/layout/DEBIAN/postinst"]:
    replace_once(
        path,
        "Next Ledger SMS Daemon 2.1.2 installation started",
        "Next Ledger SMS Daemon 2.1.3 installation started",
    )

print("Added latest-30 manual scanning, rejected-SMS restore, and one compact AI settings section.")
