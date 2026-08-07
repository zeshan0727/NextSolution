from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match in {path}, found {count}: {old[:220]!r}")
    write(path, text.replace(old, new, 1))


def regex_replace_once(path: str, pattern: str, replacement: str) -> None:
    text = read(path)
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f"Expected one regex match in {path}, found {count}: {pattern[:220]!r}")
    write(path, updated)


# ---------------------------------------------------------------------------
# App version for this device-test build.
# ---------------------------------------------------------------------------
project = "project.yml"
project_text = read(project)
project_text = re.sub(r'MARKETING_VERSION: "[^"]+"', 'MARKETING_VERSION: "1.3.51"', project_text, count=1)
project_text = re.sub(r'CURRENT_PROJECT_VERSION: "[^"]+"', 'CURRENT_PROJECT_VERSION: "59"', project_text, count=1)
write(project, project_text)


# ---------------------------------------------------------------------------
# Daemon 2.1.8: latest-20 manual scan, realtime progress and stronger
# attributedBody/typedstream recovery. The normal deterministic parser remains
# first. Unknown readable transactions still become editable review drafts.
# ---------------------------------------------------------------------------
source = "RootHideSMSQueue/Sources/main.m"
replace_once(source, 'static NSString *const kDaemonVersion = @"2.1.6";', 'static NSString *const kDaemonVersion = @"2.1.8";')

source_text = read(source)
source_text, n1 = re.subn(
    r'NSInteger approvedMessageLimit = manualRequested \? 30 : 10;',
    'NSInteger approvedMessageLimit = manualRequested ? 20 : 10;',
    source_text,
    count=1,
)
source_text, n2 = re.subn(
    r'NSInteger databaseRowLimit = manualRequested \? 30 : 250;',
    'NSInteger databaseRowLimit = manualRequested ? 20 : 250;',
    source_text,
    count=1,
)
if n1 != 1 or n2 != 1:
    raise RuntimeError(f"Could not change manual scan limits to 20 (approved={n1}, rows={n2})")
write(source, source_text)

replace_once(
    source,
    '''        @"pendingCount": @(PendingCount()),
        @"logs": gState[@"logs"] ?: @[]
''',
    '''        @"pendingCount": @(PendingCount()),
        @"scanInProgress": gState[@"scanInProgress"] ?: @NO,
        @"scanProgressCurrent": gState[@"scanProgressCurrent"] ?: @0,
        @"scanProgressTotal": gState[@"scanProgressTotal"] ?: @0,
        @"scanPhase": gState[@"scanPhase"] ?: @"Idle",
        @"logs": gState[@"logs"] ?: @[]
''',
)

# Recover the actual SMS from typedstream printable runs instead of rejecting the
# whole blob just because archive metadata appears around the message.
replace_once(
    source,
    '''    return runs.count ? CleanBankMessage([runs componentsJoinedByString:@" "]) : nil;
}
''',
    '''    if (runs.count == 0) return nil;

    NSString *joined = [runs componentsJoinedByString:@" "];
    NSString *direct = CleanBankMessage(joined);
    if (direct.length > 0) return direct;

    NSArray<NSString *> *metadataMarkers = @[
        @"streamtyped", @"NSAttributedString", @"NSMutableAttributedString",
        @"NSKeyedArchiver", @"NSDictionary", @"NSArray", @"NSObject",
        @"NS.objects", @"NS.keys", @"NS.rangeval", @"$classname", @"$classes",
        @"__kIMMessagePartAttributeName", @"__kIMFileTransferGUIDAttributeName"
    ];
    NSMutableArray<NSString *> *useful = [NSMutableArray array];
    for (NSString *run in runs) {
        NSString *candidate = CleanWhitespace(run);
        if (candidate.length == 0) continue;
        BOOL metadata = NO;
        for (NSString *marker in metadataMarkers) {
            if ([candidate rangeOfString:marker options:NSCaseInsensitiveSearch].location != NSNotFound) {
                metadata = YES;
                break;
            }
        }
        if (!metadata) [useful addObject:candidate];
    }

    NSString *filtered = CleanWhitespace([useful componentsJoinedByString:@" "]);
    NSString *clean = CleanBankMessage(filtered);
    if (clean.length > 0) return clean;

    NSString *lower = filtered.lowercaseString;
    BOOL hasCurrency = Capture(@"\\b(QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9]", filtered, 1).length > 0;
    BOOL transactional = [lower containsString:@"a/c debit"] ||
        [lower containsString:@"account debit"] || [lower containsString:@"card payment"] ||
        [lower containsString:@"used for"] || [lower containsString:@"credited"] ||
        [lower containsString:@"withdrawal"] || [lower containsString:@"transfer"] ||
        [lower containsString:@"fawran"] || [lower containsString:@"payment"];
    return hasCurrency && transactional ? filtered : nil;
}
''',
)

# Realtime manual-scan status is written to the app console JSON on every row.
replace_once(
    source,
    '''    NSInteger draftFailures = 0;

    while (sqlite3_step(statement) == SQLITE_ROW) {
''',
    '''    NSInteger draftFailures = 0;

    if (manualRequested) {
        gState[@"scanInProgress"] = @YES;
        gState[@"scanProgressCurrent"] = @0;
        gState[@"scanProgressTotal"] = @(databaseRowLimit);
        gState[@"scanPhase"] = @"Starting latest-20 SMS scan";
        WriteConsole(@"Manual scan started. Reading the latest 20 incoming messages…");
    }

    while (sqlite3_step(statement) == SQLITE_ROW) {
''',
)
replace_once(
    source,
    '''        databaseRowsRead += 1;
        sqlite3_int64 rowID = sqlite3_column_int64(statement, 0);
''',
    '''        databaseRowsRead += 1;
        if (manualRequested) {
            gState[@"scanProgressCurrent"] = @(MIN(databaseRowsRead, databaseRowLimit));
            gState[@"scanPhase"] = [NSString stringWithFormat:@"Scanning message %ld of %ld", (long)MIN(databaseRowsRead, databaseRowLimit), (long)databaseRowLimit];
            WriteConsole(@"Manual scan in progress…");
        }
        sqlite3_int64 rowID = sqlite3_column_int64(statement, 0);
''',
)
replace_once(
    source,
    '''    gState[@"automaticScanIntervalHours"] = @(ConfiguredAutomaticScanHours(config));
    if (parseFailures > 0) {
''',
    '''    gState[@"automaticScanIntervalHours"] = @(ConfiguredAutomaticScanHours(config));
    if (manualRequested) {
        gState[@"scanInProgress"] = @NO;
        gState[@"scanProgressCurrent"] = @(databaseRowLimit);
        gState[@"scanProgressTotal"] = @(databaseRowLimit);
        gState[@"scanPhase"] = @"Completed";
    }
    if (parseFailures > 0) {
''',
)

# Regression test for the exact failure mode seen on-device: the transaction
# text is split into printable runs inside an attributedBody typedstream blob.
replace_once(
    source,
    '''    BOOL passed = YES;
    for (NSDictionary *test in tests) {
''',
    '''    BOOL passed = YES;
    const unsigned char syntheticAttributedBody[] =
        "streamtyped\\0NSAttributedString\\0NSString\\0CUR1 a/c debit\\0QAR 350.00\\0for Card Payment\\0at 20:01, 07-Aug-26\\0CUR1 Balance: QAR 1,208.55\\0Card Available Balance: QAR -3,345.91\\0";
    NSString *recoveredBody = TextFromAttributedBody(
        syntheticAttributedBody,
        (int)sizeof(syntheticAttributedBody) - 1
    );
    NSDictionary *recoveredParsed = recoveredBody.length
        ? ReviewDraftForUnrecognizedBankSMS(recoveredBody, NSDate.date)
        : nil;
    BOOL bodyRecoveryPassed = recoveredParsed &&
        [recoveredParsed[@"kind"] isEqualToString:@"reviewTransfer"] &&
        [recoveredParsed[@"cardEnding"] isEqualToString:@"CUR1"] &&
        [recoveredParsed[@"amount"] compare:[NSDecimalNumber decimalNumberWithString:@"350"]] == NSOrderedSame;
    passed = passed && bodyRecoveryPassed;
    [results addObject:@{
        @"name": @"attributed-body CUR1 recovery",
        @"passed": @(bodyRecoveryPassed),
        @"parsed": recoveredParsed ?: @{}
    }];

    for (NSDictionary *test in tests) {
''',
)

# Package metadata version.
replace_once("RootHideSMSQueue/control", "Version: 2.1.6", "Version: 2.1.8")
for path in ["RootHideSMSQueue/postinst", "RootHideSMSQueue/layout/DEBIAN/postinst"]:
    replace_once(
        path,
        "Next Ledger SMS Daemon 2.1.6 installation started",
        "Next Ledger SMS Daemon 2.1.8 installation started",
    )


# ---------------------------------------------------------------------------
# App snapshot + realtime console progress.
# ---------------------------------------------------------------------------
service = "DailyLedger/Services/SMSImportConsoleService.swift"
replace_once(
    service,
    '''    var pendingCount = 0
    var logs: [SMSImportLogEntry] = []
''',
    '''    var pendingCount = 0
    var scanInProgress: Bool?
    var scanProgressCurrent: Int?
    var scanProgressTotal: Int?
    var scanPhase: String?
    var logs: [SMSImportLogEntry] = []
''',
)

view = "DailyLedger/Views/SMSImportConsoleView.swift"
replace_once(
    view,
    '''    @State private var notice: String?
''',
    '''    @AppStorage("SMSAIRecognitionEnabledV1") private var aiRecognitionEnabled = false
    @State private var localManualScan = false
    @State private var manualScanRequestedAt: Date?
    @State private var aiProcessing = false
    @State private var aiProcessedCount = 0
    @State private var notice: String?
''',
)

# First timer in the file belongs to the console; logs can keep their slower timer.
view_text = read(view)
view_text, timer_count = re.subn(
    r'Timer\.publish\(every: 2, on: \.main, in: \.common\)\.autoconnect\(\)',
    'Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()',
    view_text,
    count=1,
)
if timer_count != 1:
    raise RuntimeError(f"Expected one console timer, changed {timer_count}")
write(view, view_text)

replace_once(
    view,
    '''                Button {
                    saveConfiguration(requestScan: true)
                } label: {
                    Label("Manual Scan · Latest 30 SMS", systemImage: "arrow.clockwise.circle.fill")
                }
''',
    '''                Button {
                    startManualScan()
                } label: {
                    Label(localManualScan || snapshot.scanInProgress == true ? "Scanning Latest 20 SMS…" : "Manual Scan · Latest 20 SMS", systemImage: "arrow.clockwise.circle.fill")
                }
                .disabled(localManualScan || snapshot.scanInProgress == true)

                if localManualScan || snapshot.scanInProgress == true {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: scanProgress)
                        HStack {
                            Text(snapshot.scanPhase ?? "Waiting for daemon…")
                            Spacer()
                            Text("\\(scanProgressPercent)%")
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Toggle("AI Recognition for Unrecognized SMS", isOn: $aiRecognitionEnabled)
                Text("When enabled, only SMS that the local parser cannot classify confidently is sent to your configured OpenAI or DeepSeek account. AI results remain review suggestions; they are not blindly recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if aiProcessing {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("AI is recognizing unclassified SMS drafts…")
                            .font(.caption)
                    }
                } else if aiProcessedCount > 0 {
                    Text("AI prepared \\(aiProcessedCount) recognition suggestion\\(aiProcessedCount == 1 ? \"\" : \"s\") for review.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
''',
)

# Installer diagnostic content now opens on its own page instead of occupying
# the main SMS console.
regex_replace_once(
    view,
    r'''            if !installerDiagnostic\.isEmpty \{\n                Section\("Installer Diagnostic"\) \{\n                    Text\(installerDiagnostic\)\n                        \.font\(\.caption\.monospaced\(\)\)\n                        \.textSelection\(\.enabled\)\n                \}\n            \}\n''',
    '''            Section {
                NavigationLink {
                    SMSInstallerDiagnosticView()
                } label: {
                    Label("Installer Diagnostics", systemImage: "wrench.and.screwdriver.fill")
                }
            }
''',
)

# Do not interrupt a manual scan with an alert; the live progress UI is the feedback.
replace_once(
    view,
    '''            notice = requestScan
                ? "The daemon was asked to scan recent bank messages."
                : "SMS import settings were saved."
''',
    '''            notice = requestScan ? nil : "SMS import settings were saved."
''',
)

replace_once(
    view,
    '''    private func refresh() {
        snapshot = SMSImportConsoleService.loadSnapshot()
        installerDiagnostic = SMSImportConsoleService.loadInstallerDiagnostic()
        draftCount = SMSImportConsoleService.loadDrafts().count
    }
''',
    '''    private func startManualScan() {
        localManualScan = true
        manualScanRequestedAt = Date()
        saveConfiguration(requestScan: true)
        refresh()
    }

    private var scanProgress: Double {
        let total = max(snapshot.scanProgressTotal ?? 20, 1)
        let current = min(max(snapshot.scanProgressCurrent ?? 0, 0), total)
        return Double(current) / Double(total)
    }

    private var scanProgressPercent: Int {
        Int((scanProgress * 100).rounded())
    }

    private func refresh() {
        snapshot = SMSImportConsoleService.loadSnapshot()
        installerDiagnostic = SMSImportConsoleService.loadInstallerDiagnostic()
        draftCount = SMSImportConsoleService.loadDrafts().count

        if localManualScan,
           snapshot.scanInProgress != true,
           let requested = manualScanRequestedAt,
           let completed = snapshot.lastScanDate,
           completed >= requested.addingTimeInterval(-1) {
            localManualScan = false
        }
        startAIRecognitionIfNeeded()
    }

    private func startAIRecognitionIfNeeded() {
        guard aiRecognitionEnabled, !aiProcessing, SMSAIRecognitionService.isAvailable else { return }
        let drafts = SMSImportConsoleService.loadDrafts().filter {
            $0.kind.hasPrefix("review") && SMSAIRecognitionService.cachedResult(for: $0.id) == nil
        }
        guard !drafts.isEmpty else { return }
        aiProcessing = true
        Task {
            var completed = 0
            for draft in drafts.prefix(20) {
                if (try? await SMSAIRecognitionService.analyze(draft: draft)) != nil {
                    completed += 1
                }
            }
            await MainActor.run {
                aiProcessedCount += completed
                aiProcessing = false
            }
        }
    }
''',
)

installer_view = r'''

private struct SMSInstallerDiagnosticView: View {
    @State private var diagnostic = ""

    var body: some View {
        List {
            Section("Installer Diagnostic") {
                if diagnostic.isEmpty {
                    Text("No installer diagnostic is available yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(diagnostic)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            Section {
                Button("Refresh") { reload() }
            }
        }
        .navigationTitle("Installer Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
    }

    private func reload() {
        diagnostic = SMSImportConsoleService.loadInstallerDiagnostic()
    }
}
'''
view_text = read(view).rstrip()
if "private struct SMSInstallerDiagnosticView" not in view_text:
    view_text += installer_view
write(view, view_text + "\n")


# ---------------------------------------------------------------------------
# AI recognizer. It intentionally receives only one unrecognized SMS at a time,
# never the user's ledger, balances, contacts or transaction history.
# ---------------------------------------------------------------------------
ai_service = r'''import Foundation

struct SMSAIRecognitionResult: Codable, Equatable {
    var transactionType: String
    var amount: String?
    var currency: String?
    var accountAlias: String?
    var vendor: String?
    var category: String?
    var confidence: Double
    var reason: String?
    var provider: String?
}

enum SMSAIRecognitionError: LocalizedError {
    case noProvider
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noProvider:
            return "Add an OpenAI or DeepSeek API key in Settings first."
        case .invalidResponse:
            return "AI did not return a valid transaction classification."
        }
    }
}

enum SMSAIRecognitionService {
    static var isAvailable: Bool {
        OpenAIService.shared.hasAPIKey || DeepSeekService.shared.hasAPIKey
    }

    static func cachedResult(for id: UUID) -> SMSAIRecognitionResult? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(id)),
              let result = try? JSONDecoder().decode(SMSAIRecognitionResult.self, from: data) else {
            return nil
        }
        return result
    }

    @discardableResult
    static func analyze(draft: SMSImportDraft) async throws -> SMSAIRecognitionResult {
        let response: String
        let provider: String
        let system = """
        You classify one bank SMS for a personal ledger. Return JSON only. Never invent an account, beneficiary, amount, currency, date, or direction that the SMS does not support. transactionType must be income, expense, or transfer. Use transfer for card payments between the user's own bank/current/card accounts, cash withdrawals, remittances between accounts, or explicit transfers. Confidence must be 0 to 1. Keep vendor and category short.
        """
        let prompt = """
        Classify this bank SMS. JSON schema:
        {"transactionType":"income|expense|transfer","amount":"number or null","currency":"code or null","accountAlias":"source alias/card ending if stated or null","vendor":"counterparty/purpose or null","category":"short category","confidence":0.0,"reason":"short reason"}

        SMS:
        \(draft.details)
        """

        if OpenAIService.shared.hasAPIKey {
            provider = "OpenAI"
            let model = UserDefaults.standard.string(forKey: "OpenAIModel") ?? "gpt-4.1-nano"
            response = try await OpenAIService.shared.request(
                messages: [
                    OpenAIMessage(role: "system", content: system),
                    OpenAIMessage(role: "user", content: prompt)
                ],
                model: model,
                maxTokens: 320
            )
        } else if DeepSeekService.shared.hasAPIKey {
            provider = "DeepSeek"
            let model = UserDefaults.standard.string(forKey: "DeepSeekModel") ?? "deepseek-v4-flash"
            response = try await DeepSeekService.shared.request(
                messages: [
                    DeepSeekMessage(role: "system", content: system),
                    DeepSeekMessage(role: "user", content: prompt)
                ],
                model: model,
                maxTokens: 320
            )
        } else {
            throw SMSAIRecognitionError.noProvider
        }

        guard let data = jsonData(from: response),
              var result = try? JSONDecoder().decode(SMSAIRecognitionResult.self, from: data) else {
            throw SMSAIRecognitionError.invalidResponse
        }
        let allowed = ["income", "expense", "transfer"]
        result.transactionType = result.transactionType.lowercased()
        guard allowed.contains(result.transactionType) else {
            throw SMSAIRecognitionError.invalidResponse
        }
        result.confidence = min(max(result.confidence, 0), 1)
        result.provider = provider
        if let encoded = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(encoded, forKey: cacheKey(draft.id))
        }
        return result
    }

    static func clearCache(for id: UUID) {
        UserDefaults.standard.removeObject(forKey: cacheKey(id))
    }

    private static func cacheKey(_ id: UUID) -> String {
        "SMSAIRecognitionV1.\(id.uuidString)"
    }

    private static func jsonData(from raw: String) -> Data? {
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"), start <= end else { return nil }
        return String(raw[start...end]).data(using: .utf8)
    }
}
'''
write("DailyLedger/Services/SMSAIRecognitionService.swift", ai_service)


# ---------------------------------------------------------------------------
# Editable SMS draft screen: apply cached AI suggestions automatically and allow
# explicit re-analysis. User still controls From/To accounts and final approval.
# ---------------------------------------------------------------------------
inbox = "DailyLedger/Views/SMSDraftInboxView.swift"
replace_once(
    inbox,
    '''    @State private var notice: String?

    var body: some View {
''',
    '''    @AppStorage("SMSAIRecognitionEnabledV1") private var aiRecognitionEnabled = false
    @State private var aiAnalyzing = false
    @State private var aiRecognitionNote: String?
    @State private var notice: String?

    var body: some View {
''',
)
replace_once(
    inbox,
    '''            Section("Description") {
''',
    '''            if draft.kind.hasPrefix("review") {
                Section("AI Recognition") {
                    if aiRecognitionEnabled {
                        Button {
                            Task { await analyzeWithAI(force: true) }
                        } label: {
                            Label(aiAnalyzing ? "Analyzing SMS…" : "Analyze with AI", systemImage: "sparkles")
                        }
                        .disabled(aiAnalyzing || !SMSAIRecognitionService.isAvailable)

                        if aiAnalyzing { ProgressView() }
                        if let aiRecognitionNote {
                            Text(aiRecognitionNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !SMSAIRecognitionService.isAvailable {
                            Text("Add an OpenAI or DeepSeek API key in Settings to use AI recognition.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("AI Recognition is off. Enable it in the SMS Import Console if you want AI to classify messages the local parser cannot recognize confidently.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Description") {
''',
)
replace_once(
    inbox,
    '''        .onAppear(perform: prepareDefaults)
        .onChange(of: reviewType) { newValue in
''',
    '''        .onAppear(perform: prepareDefaults)
        .task {
            if aiRecognitionEnabled && draft.kind.hasPrefix("review") {
                await analyzeWithAI(force: false)
            }
        }
        .onChange(of: reviewType) { newValue in
''',
)
replace_once(
    inbox,
    '''        if reviewType == .transfer { category = "Transfer" }
    }

    private func approve() {
''',
    '''        if reviewType == .transfer { category = "Transfer" }
        if let cached = SMSAIRecognitionService.cachedResult(for: draft.id) {
            applyAIRecognition(cached)
        }
    }

    @MainActor
    private func analyzeWithAI(force: Bool) async {
        guard draft.kind.hasPrefix("review"), aiRecognitionEnabled else { return }
        if !force, let cached = SMSAIRecognitionService.cachedResult(for: draft.id) {
            applyAIRecognition(cached)
            return
        }
        guard SMSAIRecognitionService.isAvailable else { return }
        aiAnalyzing = true
        defer { aiAnalyzing = false }
        do {
            if force { SMSAIRecognitionService.clearCache(for: draft.id) }
            let result = try await SMSAIRecognitionService.analyze(draft: draft)
            applyAIRecognition(result)
        } catch {
            aiRecognitionNote = error.localizedDescription
        }
    }

    @MainActor
    private func applyAIRecognition(_ result: SMSAIRecognitionResult) {
        switch result.transactionType {
        case "income": reviewType = .income
        case "transfer": reviewType = .transfer
        default: reviewType = .expense
        }
        if let amount = result.amount?.replacingOccurrences(of: ",", with: ""),
           Decimal(string: amount) != nil {
            amountText = amount
        }
        if let value = result.vendor?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            vendor = value
        }
        if let value = result.category?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            category = reviewType == .transfer ? "Transfer" : value
        }
        if reviewType == .transfer { category = "Transfer" }

        if accountID == nil,
           let alias = result.accountAlias?.lowercased(), !alias.isEmpty,
           let account = activeAccounts.first(where: { $0.name.lowercased().contains(alias) }) {
            accountID = account.id
        }
        let confidence = Int((result.confidence * 100).rounded())
        let provider = result.provider ?? "AI"
        let reason = result.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        aiRecognitionNote = reason.isEmpty
            ? "\(provider) confidence: \(confidence)%"
            : "\(provider) confidence: \(confidence)% · \(reason)"
    }

    private func approve() {
''',
)

print("Prepared Next Ledger 1.3.51 with realtime latest-20 SMS scanning, typedstream recovery, separate installer diagnostics and AI recognition.")
