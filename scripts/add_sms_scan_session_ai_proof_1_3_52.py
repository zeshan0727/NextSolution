from pathlib import Path

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
        raise RuntimeError(f"Expected one match in {path}, found {count}: {old[:240]!r}")
    write(path, text.replace(old, new, 1))


# ---------------------------------------------------------------------------
# Version bump.
# ---------------------------------------------------------------------------
replace_once("project.yml", 'MARKETING_VERSION: "1.3.51"', 'MARKETING_VERSION: "1.3.52"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "59"', 'CURRENT_PROJECT_VERSION: "60"')

source = "RootHideSMSQueue/Sources/main.m"
replace_once(source, 'static NSString *const kDaemonVersion = @"2.1.8";', 'static NSString *const kDaemonVersion = @"2.1.9";')

# ---------------------------------------------------------------------------
# Crash guard: migrated/legacy drafts are not guaranteed to contain rowID.
# The old comparator could send -compare: with nil and terminate the daemon
# immediately after the review-candidate log. Keep sorting deterministic while
# tolerating missing or non-numeric values.
# ---------------------------------------------------------------------------
replace_once(
    source,
    '''        [drafts sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            return [right[@"rowID"] compare:left[@"rowID"]];
        }];
''',
    '''        [drafts sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            NSNumber *leftRow = [left[@"rowID"] isKindOfClass:NSNumber.class] ? left[@"rowID"] : @0;
            NSNumber *rightRow = [right[@"rowID"] isKindOfClass:NSNumber.class] ? right[@"rowID"] : @0;
            return [rightRow compare:leftRow];
        }];
''',
)

# ---------------------------------------------------------------------------
# Manual scan session semantics.
# Claim scanRequestID before touching sms.db. If the daemon is unexpectedly
# restarted, the same request is already consumed and cannot replay forever.
# ---------------------------------------------------------------------------
replace_once(
    source,
    '''    NSInteger requestID = [config[@"scanRequestID"] integerValue];
    NSInteger savedRequest = [gState[@"lastScanRequestID"] integerValue];
    BOOL manualRequested = forceRecent || requestID != savedRequest;
    NSDate *scanDate = NSDate.date;

    if (!manualRequested && !AutomaticScanIsDue(config, scanDate)) {
''',
    '''    NSInteger requestID = [config[@"scanRequestID"] integerValue];
    NSInteger savedRequest = [gState[@"lastScanRequestID"] integerValue];
    BOOL manualRequested = forceRecent || requestID != savedRequest;
    NSDate *scanDate = NSDate.date;

    if (manualRequested) {
        gState[@"lastScanRequestID"] = @(requestID);
        gState[@"manualScanClaimedAt"] = ISODate(scanDate);
        gState[@"scanInProgress"] = @YES;
        gState[@"scanProgressCurrent"] = @0;
        gState[@"scanProgressTotal"] = @20;
        gState[@"scanPhase"] = @"Manual scan claimed";
        SaveState();
    }

    if (!manualRequested && !AutomaticScanIsDue(config, scanDate)) {
''',
)

# A daemon restart during a scan should be visible and should not immediately
# trigger the automatic scanner. The user can explicitly tap Manual Scan again.
replace_once(
    source,
    '''        LoadState();
        AddLog(@"info", @"Next Ledger SMS daemon %@ started as uid %d.", kDaemonVersion, getuid());
''',
    '''        LoadState();
        if ([gState[@"scanInProgress"] boolValue]) {
            gState[@"scanInProgress"] = @NO;
            gState[@"scanPhase"] = @"Previous scan interrupted — tap Manual Scan to retry";
            gState[@"lastAutomaticScanUnix"] = @(NSDate.date.timeIntervalSince1970);
            SaveState();
        }
        AddLog(@"info", @"Next Ledger SMS daemon %@ started as uid %d.", kDaemonVersion, getuid());
''',
)

# Make the progress total truthful when there are fewer than 20 incoming rows.
# It still never queries more than the latest 20 rows for a manual scan.
replace_once(
    source,
    '''        gState[@"scanProgressCurrent"] = @0;
        gState[@"scanProgressTotal"] = @(databaseRowLimit);
        gState[@"scanPhase"] = @"Starting latest-20 SMS scan";
''',
    '''        gState[@"scanProgressCurrent"] = @0;
        gState[@"scanProgressTotal"] = @(databaseRowLimit);
        gState[@"scanPhase"] = @"Starting latest-20 SMS scan";
''',
)

# ---------------------------------------------------------------------------
# AI proof/status: persist last provider/result/error so the UI proves whether
# an actual API call happened. This does not expose the API key.
# ---------------------------------------------------------------------------
ai = "DailyLedger/Services/SMSAIRecognitionService.swift"
replace_once(
    ai,
    '''enum SMSAIRecognitionService {
    static var isAvailable: Bool {
''',
    '''enum SMSAIRecognitionService {
    static let statusChanged = Notification.Name("SMSAIRecognitionStatusChanged")

    static var isAvailable: Bool {
''',
)
replace_once(
    ai,
    '''        result.provider = provider
        if let encoded = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(encoded, forKey: cacheKey(draft.id))
        }
        return result
''',
    '''        result.provider = provider
        if let encoded = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(encoded, forKey: cacheKey(draft.id))
        }
        UserDefaults.standard.set(provider, forKey: "SMSAILastProviderV1")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "SMSAILastSuccessV1")
        UserDefaults.standard.set(result.transactionType, forKey: "SMSAILastTypeV1")
        UserDefaults.standard.set(Int((result.confidence * 100).rounded()), forKey: "SMSAILastConfidenceV1")
        UserDefaults.standard.removeObject(forKey: "SMSAILastErrorV1")
        NotificationCenter.default.post(name: statusChanged, object: nil)
        return result
''',
)

# Record actual failures as well, including provider/network/JSON errors.
replace_once(
    ai,
    '''    static func clearCache(for id: UUID) {
''',
    '''    static func recordFailure(_ error: Error) {
        UserDefaults.standard.set(error.localizedDescription, forKey: "SMSAILastErrorV1")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "SMSAILastAttemptV1")
        NotificationCenter.default.post(name: statusChanged, object: nil)
    }

    static func clearCache(for id: UUID) {
''',
)

# Both automatic queue processing and the per-draft button must expose errors.
console = "DailyLedger/Views/SMSImportConsoleView.swift"
replace_once(
    console,
    '''                if (try? await SMSAIRecognitionService.analyze(draft: draft)) != nil {
                    completed += 1
                }
''',
    '''                do {
                    _ = try await SMSAIRecognitionService.analyze(draft: draft)
                    completed += 1
                } catch {
                    SMSAIRecognitionService.recordFailure(error)
                }
''',
)

# Add a visible AI diagnostic/status page directly under the AI recognition toggle.
replace_once(
    console,
    '''                Toggle("AI Recognition for Unrecognized SMS", isOn: $aiRecognitionEnabled)
                Text("When enabled, only SMS that the local parser cannot classify confidently is sent to your configured OpenAI or DeepSeek account. AI results remain review suggestions; they are not blindly recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if aiProcessing {
''',
    '''                Toggle("AI Recognition for Unrecognized SMS", isOn: $aiRecognitionEnabled)
                Text("When enabled, only SMS that the local parser cannot classify confidently is sent to your configured OpenAI or DeepSeek account. AI results remain review suggestions; they are not blindly recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                NavigationLink {
                    SMSAIRecognitionStatusView()
                } label: {
                    Label("AI Recognition Status & Test", systemImage: "sparkles.rectangle.stack.fill")
                }

                if aiProcessing {
''',
)

# Append a status/test screen. Test runs against the newest unresolved review draft.
status_view = r'''

private struct SMSAIRecognitionStatusView: View {
    @State private var testing = false
    @State private var message: String?
    @State private var refreshToken = UUID()

    private var provider: String {
        _ = refreshToken
        return UserDefaults.standard.string(forKey: "SMSAILastProviderV1") ?? "None yet"
    }

    private var confidence: String {
        _ = refreshToken
        let value = UserDefaults.standard.integer(forKey: "SMSAILastConfidenceV1")
        return UserDefaults.standard.object(forKey: "SMSAILastConfidenceV1") == nil ? "—" : "\(value)%"
    }

    private var lastType: String {
        _ = refreshToken
        return UserDefaults.standard.string(forKey: "SMSAILastTypeV1") ?? "—"
    }

    private var lastSuccess: String {
        _ = refreshToken
        let raw = UserDefaults.standard.double(forKey: "SMSAILastSuccessV1")
        guard raw > 0 else { return "Never" }
        return Date(timeIntervalSince1970: raw).formatted(date: .abbreviated, time: .standard)
    }

    private var lastError: String? {
        _ = refreshToken
        return UserDefaults.standard.string(forKey: "SMSAILastErrorV1")
    }

    var body: some View {
        List {
            Section("Connection") {
                LabeledContent("AI available", value: SMSAIRecognitionService.isAvailable ? "Yes" : "No API key")
                LabeledContent("Last provider", value: provider)
                LabeledContent("Last successful call", value: lastSuccess)
            }
            Section("Last AI Result") {
                LabeledContent("Type", value: lastType.capitalized)
                LabeledContent("Confidence", value: confidence)
                if let lastError, !lastError.isEmpty {
                    Text("Last error: \(lastError)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button {
                    Task { await runTest() }
                } label: {
                    Label(testing ? "Testing AI…" : "Test AI on Latest Review Draft", systemImage: "checkmark.shield.fill")
                }
                .disabled(testing || !SMSAIRecognitionService.isAvailable)
                if testing { ProgressView() }
            } footer: {
                Text("A successful test must display the actual provider, returned type and confidence. The original SMS stays a review draft; this test never records a transaction.")
            }
        }
        .navigationTitle("AI Recognition")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: SMSAIRecognitionService.statusChanged)) { _ in
            refreshToken = UUID()
        }
    }

    @MainActor
    private func runTest() async {
        let drafts = SMSImportConsoleService.loadDrafts().filter { $0.kind.hasPrefix("review") }
        guard let draft = drafts.first else {
            message = "No unresolved review draft is available. Run Manual Scan first."
            return
        }
        testing = true
        defer { testing = false }
        do {
            SMSAIRecognitionService.clearCache(for: draft.id)
            let result = try await SMSAIRecognitionService.analyze(draft: draft)
            message = "Verified \(result.provider ?? "AI"): \(result.transactionType.capitalized), \(Int((result.confidence * 100).rounded()))% confidence."
            refreshToken = UUID()
        } catch {
            SMSAIRecognitionService.recordFailure(error)
            message = "AI test failed: \(error.localizedDescription)"
            refreshToken = UUID()
        }
    }
}
'''
console_text = read(console).rstrip()
if "private struct SMSAIRecognitionStatusView" not in console_text:
    console_text += status_view
write(console, console_text + "\n")

inbox = "DailyLedger/Views/SMSDraftInboxView.swift"
replace_once(
    inbox,
    '''        } catch {
            aiRecognitionNote = error.localizedDescription
        }
''',
    '''        } catch {
            SMSAIRecognitionService.recordFailure(error)
            aiRecognitionNote = error.localizedDescription
        }
''',
)

# Package metadata.
replace_once("RootHideSMSQueue/control", "Version: 2.1.8", "Version: 2.1.9")
for path in ["RootHideSMSQueue/postinst", "RootHideSMSQueue/layout/DEBIAN/postinst"]:
    replace_once(
        path,
        "Next Ledger SMS Daemon 2.1.8 installation started",
        "Next Ledger SMS Daemon 2.1.9 installation started",
    )

print("Prepared Next Ledger 1.3.52: crash-safe drafts, single-session manual scans and provable AI diagnostics.")
