from pathlib import Path
import re

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
        raise RuntimeError(f"Expected one match in {path}, found {count}: {old[:220]!r}")
    write(path, text.replace(old, new, 1))

# ---------------------------------------------------------------------------
# Release: app 1.3.59 build 67, daemon 2.2.1.
# ---------------------------------------------------------------------------
replace_once("project.yml", 'MARKETING_VERSION: "1.3.58"', 'MARKETING_VERSION: "1.3.59"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "66"', 'CURRENT_PROJECT_VERSION: "67"')

source = "RootHideSMSQueue/Sources/main.m"
replace_once(source, 'static NSString *const kDaemonVersion = @"2.2.0";', 'static NSString *const kDaemonVersion = @"2.2.1";')

# Latest-15 review queue lives in the same protected app-support directory used
# by drafts/AI candidates. Manual scans write this queue directly and do not rely
# on approved-bank filtering.
text = read(source)
path_anchor = '''static NSString *DraftLockPath(void) {
'''
if path_anchor not in text:
    raise RuntimeError("DraftLockPath anchor not found")
text = text.replace(path_anchor, '''static NSString *LatestReviewPath(void) {
    NSString *directory = AppSupportDirectory();
    return directory ? [directory stringByAppendingPathComponent:@"sms-latest15-review.json"] : nil;
}

''' + path_anchor, 1)
write(source, text)

# Independent full-text recovery for review mode. The ordinary parser may clean
# text aggressively; this path preserves m.text verbatim and only strips archive
# metadata when attributedBody is the sole source.
text = read(source)
maximum_anchor = 'static sqlite3_int64 MaximumRowID(sqlite3 *database) {'
if maximum_anchor not in text:
    raise RuntimeError("MaximumRowID anchor not found")
helper = r'''static NSString *ReviewTextFromAttributedBody(const void *bytes, int length) {
    if (!bytes || length <= 0) return nil;
    const unsigned char *raw = bytes;
    NSMutableArray<NSString *> *runs = [NSMutableArray array];
    int start = -1;
    for (int index = 0; index <= length; index++) {
        BOOL printable = index < length && raw[index] >= 32 && raw[index] <= 126;
        if (printable && start < 0) start = index;
        if (!printable && start >= 0) {
            int runLength = index - start;
            if (runLength >= 3) {
                NSString *run = [[NSString alloc] initWithBytes:raw + start
                                                         length:(NSUInteger)runLength
                                                       encoding:NSUTF8StringEncoding];
                if (run.length > 0) [runs addObject:run];
            }
            start = -1;
        }
    }
    if (runs.count == 0) return nil;

    NSArray<NSString *> *metadata = @[
        @"streamtyped", @"NSAttributedString", @"NSMutableAttributedString",
        @"NSString", @"NSDictionary", @"NSArray", @"NSObject", @"NSValue",
        @"NS.objects", @"NS.keys", @"NS.rangeval", @"$classname", @"$classes",
        @"__kIMMessagePartAttributeName", @"__kIMFileTransferGUIDAttributeName"
    ];
    NSMutableArray<NSString *> *useful = [NSMutableArray array];
    for (NSString *run in runs) {
        BOOL archiveMetadata = NO;
        for (NSString *marker in metadata) {
            if ([run rangeOfString:marker options:NSCaseInsensitiveSearch].location != NSNotFound) {
                archiveMetadata = YES;
                break;
            }
        }
        if (!archiveMetadata) [useful addObject:run];
    }
    NSString *result = [[useful componentsJoinedByString:@"\n"]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return result.length ? result : nil;
}

static NSString *ReviewMessageText(sqlite3_stmt *statement) {
    const unsigned char *textBytes = sqlite3_column_text(statement, 2);
    if (textBytes) {
        NSString *value = [NSString stringWithUTF8String:(const char *)textBytes];
        if (value.length > 0) return value; // preserve complete message text
    }

    const void *bytes = sqlite3_column_blob(statement, 3);
    int length = sqlite3_column_bytes(statement, 3);
    if (!bytes || length <= 0) return nil;
    NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)length];
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        id decoded = [NSKeyedUnarchiver unarchiveObjectWithData:data];
#pragma clang diagnostic pop
        if ([decoded isKindOfClass:NSAttributedString.class]) {
            NSString *value = [decoded string];
            if (value.length > 0) return value;
        }
        if ([decoded isKindOfClass:NSString.class] && [decoded length] > 0) return decoded;
    } @catch (__unused NSException *exception) {}
    return ReviewTextFromAttributedBody(bytes, length);
}

static NSInteger CollectLatestIncomingMessagesForReview(sqlite3 *database, NSInteger limit) {
    if (!database || limit <= 0) return 0;
    const char *query =
        "SELECT m.ROWID, COALESCE(m.guid, ''), m.text, m.attributedBody, m.date, COALESCE(h.id, '') "
        "FROM message m LEFT JOIN handle h ON m.handle_id = h.ROWID "
        "WHERE m.is_from_me = 0 AND (m.text IS NOT NULL OR m.attributedBody IS NOT NULL) "
        "ORDER BY m.ROWID DESC LIMIT ?";

    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(database, query, -1, &statement, NULL) != SQLITE_OK) {
        AddLog(@"error", @"Latest-15 review query failed: %s", sqlite3_errmsg(database));
        return 0;
    }
    sqlite3_bind_int(statement, 1, (int)limit);

    NSMutableArray *items = [NSMutableArray array];
    NSInteger rowNumber = 0;
    while (sqlite3_step(statement) == SQLITE_ROW) {
        rowNumber += 1;
        sqlite3_int64 rowID = sqlite3_column_int64(statement, 0);
        NSString *details = ReviewMessageText(statement);
        if (details.length == 0) {
            AddLog(@"warning", @"Latest-15 row %lld had no recoverable message text.", rowID);
            continue;
        }

        const unsigned char *guidBytes = sqlite3_column_text(statement, 1);
        const unsigned char *senderBytes = sqlite3_column_text(statement, 5);
        NSString *guid = guidBytes ? [NSString stringWithUTF8String:(const char *)guidBytes] : @"";
        NSString *sender = senderBytes ? [NSString stringWithUTF8String:(const char *)senderBytes] : @"";
        NSString *sourceKey = guid.length ? guid : [NSString stringWithFormat:@"%lld|%@", rowID, details];
        NSString *identifier = DeterministicUUID(sourceKey).UUIDString;

        [items addObject:@{
            @"id": identifier,
            @"sourceKey": sourceKey,
            @"sender": sender ?: @"",
            @"rowID": @(rowID),
            @"date": ISODate(DatabaseDate(sqlite3_column_int64(statement, 4))),
            @"details": details,
            @"queuedAt": ISODate(NSDate.date)
        }];

        gState[@"scanProgressCurrent"] = @(MIN(rowNumber, limit));
        gState[@"scanProgressTotal"] = @(limit);
        gState[@"scanPhase"] = [NSString stringWithFormat:@"Collecting message %ld of %ld for review",
                                 (long)MIN(rowNumber, limit), (long)limit];
        WriteConsole(@"Collecting latest incoming messages for review…");
    }
    sqlite3_finalize(statement);

    BOOL written = WriteJSONArray(items, LatestReviewPath());
    if (!written) {
        AddLog(@"error", @"Could not write latest-15 review queue to the app container.");
        return 0;
    }
    gState[@"manualReviewCount"] = @(items.count);
    AddLog(@"success", @"Collected %ld latest incoming message%@ with complete text for user review.",
           (long)items.count, items.count == 1 ? @"" : @"s");
    return items.count;
}

'''
text = text.replace(maximum_anchor, helper + maximum_anchor, 1)
write(source, text)

# Manual scan is now a deterministic review collection path. It returns after
# collecting the latest 15 incoming rows, so it cannot continue into the old
# approved-bank/manual-history parser or auto-record those historical messages.
text = read(source)
open_anchor = '    sqlite3_busy_timeout(database, 2500);\n'
if text.count(open_anchor) != 1:
    raise RuntimeError(f"Expected one sqlite busy-timeout anchor, found {text.count(open_anchor)}")
manual_block = r'''    sqlite3_busy_timeout(database, 2500);

    if (manualRequested) {
        gState[@"scanInProgress"] = @YES;
        gState[@"scanProgressCurrent"] = @0;
        gState[@"scanProgressTotal"] = @15;
        gState[@"scanPhase"] = @"Collecting latest 15 incoming messages";
        WriteConsole(@"Manual review scan started. Collecting the latest 15 incoming messages…");

        NSInteger collected = CollectLatestIncomingMessagesForReview(database, 15);
        sqlite3_close(database);

        gState[@"lastScanRequestID"] = @(requestID);
        gState[@"lastScanDate"] = ISODate(NSDate.date);
        gState[@"scanInProgress"] = @NO;
        gState[@"scanProgressCurrent"] = @(collected);
        gState[@"scanProgressTotal"] = @15;
        gState[@"scanPhase"] = collected > 0 ? @"Completed · Ready for review" : @"Completed · No readable messages";
        SaveState();

        NSString *result = [NSString stringWithFormat:@"Manual scan finished. %ld of the latest 15 incoming messages are ready for review.", (long)collected];
        WriteConsole(result);
        return;
    }
'''
text = text.replace(open_anchor, manual_block, 1)

# Keep old generated wording/limits consistent if any remain, even though the new
# manual path returns before those branches execute.
text = text.replace('manualRequested ? 20 : 10', 'manualRequested ? 15 : 10')
text = text.replace('manualRequested ? 20 : 250', 'manualRequested ? 15 : 250')
text = text.replace('@20;', '@15;') if 'gState[@"scanProgressTotal"] = @20;' in text else text
text = text.replace('latest-20 SMS scan', 'latest-15 SMS scan')
text = text.replace('latest 20 incoming messages', 'latest 15 incoming messages')
write(source, text)

# Clear a claimed manual scan on the three early infrastructure failures instead
# of leaving scanInProgress stuck forever.
text = read(source)
for message in [
    'WriteConsole(@"Messages database not found.");\n        return;',
    'WriteConsole(@"Open Next Ledger once so its app container can be located.");\n        return;',
    'WriteConsole(@"Could not open Messages database.");\n        return;'
]:
    if message in text:
        replacement = message.replace('\n        return;', '\n        if (manualRequested) { gState[@"scanInProgress"] = @NO; gState[@"scanPhase"] = @"Manual scan failed"; SaveState(); }\n        return;')
        text = text.replace(message, replacement, 1)
write(source, text)

# Package daemon 2.2.1 metadata.
replace_once("RootHideSMSQueue/control", "Version: 2.2.0", "Version: 2.2.1")
for path in ["RootHideSMSQueue/postinst", "RootHideSMSQueue/layout/DEBIAN/postinst"]:
    text = read(path)
    text = text.replace("Next Ledger SMS Daemon 2.2.0 installation started",
                        "Next Ledger SMS Daemon 2.2.1 installation started")
    write(path, text)

# ---------------------------------------------------------------------------
# Disable the legacy automatic AI queue worker. The new latest-15 review screen
# owns AI execution explicitly, one bounded user-visible batch at a time.
# ---------------------------------------------------------------------------
app = "DailyLedger/DailyLedgerApp.swift"
text = read(app)
text = re.sub(
    r'''\n\s*\.task \{\n\s*// One bounded pass only\. No permanent AI polling loop\.\n\s*await SMSOpenAIAutoRecoveryCoordinator\.shared\.processPending\(\)\n\s*\}''',
    '', text, count=1)
text = re.sub(
    r'''\n\s*Task \{\n\s*await SMSOpenAIAutoRecoveryCoordinator\.shared\.processPending\(\)\n\s*\}''',
    '', text, count=1)
write(app, text)

# SMS AI helper for review mode uses a stable API model independent of the user's
# chat model selection. This avoids an unsupported chat-model choice breaking SMS.
ai = "DailyLedger/Services/SMSAIRecognitionService.swift"
text = read(ai)
text, model_count = re.subn(
    r'let model = UserDefaults\.standard\.string\(forKey: "OpenAIModel"\) \?\? "gpt-4\.1-nano"',
    'let model = "gpt-4.1-nano"', text, count=1)
if model_count != 1:
    raise RuntimeError(f"Expected one OpenAI SMS model selector, changed {model_count}")
write(ai, text)

# ---------------------------------------------------------------------------
# Dedicated review service/view. The collector always shows every recovered row.
# AI is optional assistance; user decides whether to send a suggestion to Drafts
# or reject it. Full message text is displayed and selectable.
# ---------------------------------------------------------------------------
review_swift = r'''import SwiftUI

struct SMSLatestReviewMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let sourceKey: String
    let sender: String
    let rowID: Int64
    let date: Date
    let details: String
    let queuedAt: Date
}

private struct SMSLatestReviewAIResult: Codable, Equatable {
    var transactionType: String
    var amount: String?
    var currency: String?
    var accountAlias: String?
    var vendor: String?
    var category: String?
    var confidence: Double
    var reason: String?
    var model: String?
}

private enum SMSLatestReviewError: LocalizedError {
    case missingKey
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingKey: return "OpenAI API key is not saved in Settings → AI."
        case .invalidResponse: return "OpenAI did not return a readable SMS classification."
        }
    }
}

enum SMSLatest15ReviewService {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static var reviewURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("DailyLedger", isDirectory: true)
            .appendingPathComponent("sms-latest15-review.json")
    }

    static func load() -> [SMSLatestReviewMessage] {
        guard let data = try? Data(contentsOf: reviewURL),
              let items = try? decoder.decode([SMSLatestReviewMessage].self, from: data) else { return [] }
        return items.sorted { $0.rowID > $1.rowID }
    }

    static func disposition(for id: UUID) -> String? {
        UserDefaults.standard.string(forKey: "SMSLatest15Disposition.\(id.uuidString)")
    }

    static func setDisposition(_ value: String?, for id: UUID) {
        let key = "SMSLatest15Disposition.\(id.uuidString)"
        if let value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }
}

private enum SMSLatest15AIService {
    static func testConnection() async throws -> String {
        guard OpenAIService.shared.hasAPIKey else { throw SMSLatestReviewError.missingKey }
        let response = try await OpenAIService.shared.request(
            messages: [OpenAIMessage(role: "user", content: "Reply with exactly: Connected")],
            model: "gpt-4.1-nano",
            maxTokens: 20
        )
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "SMSLatest15OpenAIVerifiedAt")
        UserDefaults.standard.removeObject(forKey: "SMSLatest15OpenAILastError")
        return response
    }

    static func analyze(_ item: SMSLatestReviewMessage) async throws -> SMSLatestReviewAIResult {
        guard OpenAIService.shared.hasAPIKey else { throw SMSLatestReviewError.missingKey }
        let system = """
        You help a user review one complete incoming phone message for a personal ledger. Return JSON only. Classify it as income, expense, transfer, not_transaction, or unknown. Never invent an amount, currency, account, merchant, or direction. OTPs, marketing, login/security notices, balance-only notices, declined/failed notices without a posted movement, and personal chat messages are not_transaction. If it may be financial but you cannot determine the movement, use unknown. Confidence is 0 to 1.
        """
        let prompt = """
        JSON schema:
        {"transactionType":"income|expense|transfer|not_transaction|unknown","amount":"number or null","currency":"code or null","accountAlias":"account/card hint or null","vendor":"merchant/counterparty/purpose or null","category":"short category or null","confidence":0.0,"reason":"short explanation"}

        Sender: \(item.sender.isEmpty ? "Unknown" : item.sender)
        Complete message text:
        \(item.details)
        """

        var lastError: Error?
        for model in ["gpt-4.1-nano", "gpt-4o-mini"] {
            do {
                let raw = try await OpenAIService.shared.request(
                    messages: [
                        OpenAIMessage(role: "system", content: system),
                        OpenAIMessage(role: "user", content: prompt)
                    ],
                    model: model,
                    maxTokens: 320
                )
                guard let start = raw.firstIndex(of: "{"),
                      let end = raw.lastIndex(of: "}"), start <= end,
                      let data = String(raw[start...end]).data(using: .utf8),
                      var result = try? JSONDecoder().decode(SMSLatestReviewAIResult.self, from: data) else {
                    throw SMSLatestReviewError.invalidResponse
                }
                let allowed = ["income", "expense", "transfer", "not_transaction", "unknown"]
                result.transactionType = result.transactionType.lowercased()
                guard allowed.contains(result.transactionType) else { throw SMSLatestReviewError.invalidResponse }
                result.confidence = min(max(result.confidence, 0), 1)
                result.model = model
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "SMSLatest15OpenAIVerifiedAt")
                UserDefaults.standard.removeObject(forKey: "SMSLatest15OpenAILastError")
                return result
            } catch {
                lastError = error
            }
        }
        let error = lastError ?? SMSLatestReviewError.invalidResponse
        UserDefaults.standard.set(error.localizedDescription, forKey: "SMSLatest15OpenAILastError")
        throw error
    }
}

struct SMSLatest15ReviewView: View {
    @State private var items: [SMSLatestReviewMessage] = []
    @State private var results: [UUID: SMSLatestReviewAIResult] = [:]
    @State private var aiRunning = false
    @State private var aiCurrent = 0
    @State private var aiTotal = 0
    @State private var aiLog: [String] = []
    @State private var connectionStatus = "Not tested"
    @State private var testingConnection = false
    @State private var notice: String?

    var body: some View {
        List {
            Section("Review Pipeline") {
                LabeledContent("Messages Collected", value: "\(items.count) / 15")
                LabeledContent("Pending Review", value: "\(pendingItems.count)")
                LabeledContent("OpenAI Key", value: OpenAIService.shared.hasAPIKey ? "Saved" : "Missing")
                LabeledContent("OpenAI Test", value: connectionStatus)

                HStack {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        Label(testingConnection ? "Testing…" : "Test OpenAI", systemImage: "checkmark.shield.fill")
                    }
                    .disabled(testingConnection || !OpenAIService.shared.hasAPIKey)

                    Button {
                        Task { await analyzePending() }
                    } label: {
                        Label(aiRunning ? "Analyzing…" : "Analyze Pending", systemImage: "sparkles")
                    }
                    .disabled(aiRunning || pendingItems.isEmpty || !OpenAIService.shared.hasAPIKey)
                }

                if aiRunning || aiTotal > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: aiProgress)
                        HStack {
                            Text(aiRunning ? "AI analyzing message \(min(aiCurrent + 1, max(aiTotal, 1))) of \(aiTotal)" : "AI batch finished")
                            Spacer()
                            Text("\(Int((aiProgress * 100).rounded()))%")
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if !aiLog.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI Progress Log")
                            .font(.caption.bold())
                        ForEach(Array(aiLog.suffix(8).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if items.isEmpty {
                Section {
                    Text("No latest-15 review data is available. Return to SMS Import Console and tap Collect Latest 15 Messages.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(items) { item in
                    Section {
                        HStack {
                            Text(item.sender.isEmpty ? "Unknown sender" : item.sender)
                                .font(.headline)
                            Spacer()
                            Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(item.details)
                            .font(.body)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)

                        if let disposition = SMSLatest15ReviewService.disposition(for: item.id) {
                            LabeledContent("Review Status", value: disposition.capitalized)
                        }

                        if let result = results[item.id] {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("AI Suggestion")
                                    .font(.caption.bold())
                                LabeledContent("Nature", value: result.transactionType.replacingOccurrences(of: "_", with: " ").capitalized)
                                if let amount = result.amount, let currency = result.currency {
                                    LabeledContent("Amount", value: "\(currency.uppercased()) \(amount)")
                                }
                                if let vendor = result.vendor, !vendor.isEmpty {
                                    LabeledContent("Merchant / Purpose", value: vendor)
                                }
                                LabeledContent("Confidence", value: "\(Int((result.confidence * 100).rounded()))%")
                                if let reason = result.reason, !reason.isEmpty {
                                    Text(reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        HStack {
                            Button {
                                Task { await analyzeOne(item) }
                            } label: {
                                Label("Ask AI", systemImage: "sparkles")
                            }
                            .disabled(aiRunning || !OpenAIService.shared.hasAPIKey)

                            if let result = results[item.id], canCreateDraft(result) {
                                Button {
                                    createDraft(item: item, result: result)
                                } label: {
                                    Label("Send to Drafts", systemImage: "tray.and.arrow.down.fill")
                                }
                                .buttonStyle(.borderedProminent)
                            }

                            Button(role: .destructive) {
                                SMSLatest15ReviewService.setDisposition("rejected", for: item.id)
                                results.removeValue(forKey: item.id)
                                reload()
                            } label: {
                                Label("Reject", systemImage: "xmark.circle")
                            }
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Latest 15 Messages")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reload()
            if OpenAIService.shared.hasAPIKey,
               UserDefaults.standard.double(forKey: "SMSLatest15OpenAIVerifiedAt") > 0 {
                connectionStatus = "Verified previously"
            } else if !OpenAIService.shared.hasAPIKey {
                connectionStatus = "API key required"
            }
        }
        .alert("SMS Review", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button("OK", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    private var pendingItems: [SMSLatestReviewMessage] {
        items.filter { SMSLatest15ReviewService.disposition(for: $0.id) == nil }
    }

    private var aiProgress: Double {
        guard aiTotal > 0 else { return 0 }
        return min(max(Double(aiCurrent) / Double(aiTotal), 0), 1)
    }

    private func reload() {
        items = SMSLatest15ReviewService.load()
    }

    @MainActor
    private func testConnection() async {
        testingConnection = true
        connectionStatus = "Testing…"
        defer { testingConnection = false }
        do {
            _ = try await SMSLatest15AIService.testConnection()
            connectionStatus = "Connected · API request passed"
            aiLog.append("OpenAI connection test passed using SMS model.")
        } catch {
            connectionStatus = "Error"
            aiLog.append("OpenAI test error: \(error.localizedDescription)")
            notice = "OpenAI test failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func analyzePending() async {
        let batch = pendingItems
        guard !batch.isEmpty else { return }
        aiRunning = true
        aiCurrent = 0
        aiTotal = batch.count
        aiLog = ["Starting AI review of \(batch.count) message(s)."]
        defer {
            aiRunning = false
            aiCurrent = aiTotal
        }

        for (index, item) in batch.enumerated() {
            aiCurrent = index
            aiLog.append("\(index + 1)/\(batch.count) · Reading row \(item.rowID)…")
            do {
                let result = try await SMSLatest15AIService.analyze(item)
                results[item.id] = result
                connectionStatus = "Connected · AI responding"
                aiLog.append("\(index + 1)/\(batch.count) · \(result.transactionType) · \(Int((result.confidence * 100).rounded()))%")
            } catch {
                connectionStatus = "Error"
                aiLog.append("\(index + 1)/\(batch.count) · ERROR: \(error.localizedDescription)")
                // Stop the batch on a connection/API error; do not loop endlessly.
                notice = "AI stopped at message \(index + 1): \(error.localizedDescription)"
                return
            }
            aiCurrent = index + 1
        }
        aiLog.append("AI review finished. Review each suggestion, then Send to Drafts or Reject.")
    }

    @MainActor
    private func analyzeOne(_ item: SMSLatestReviewMessage) async {
        aiRunning = true
        aiCurrent = 0
        aiTotal = 1
        aiLog.append("Analyzing row \(item.rowID)…")
        defer {
            aiRunning = false
            aiCurrent = 1
        }
        do {
            let result = try await SMSLatest15AIService.analyze(item)
            results[item.id] = result
            connectionStatus = "Connected · AI responding"
            aiLog.append("Row \(item.rowID): \(result.transactionType), \(Int((result.confidence * 100).rounded()))%")
        } catch {
            connectionStatus = "Error"
            aiLog.append("Row \(item.rowID) ERROR: \(error.localizedDescription)")
            notice = "AI error: \(error.localizedDescription)"
        }
    }

    private func canCreateDraft(_ result: SMSLatestReviewAIResult) -> Bool {
        guard ["income", "expense", "transfer"].contains(result.transactionType),
              let amount = result.amount?.replacingOccurrences(of: ",", with: ""),
              Decimal(string: amount) != nil,
              let currency = result.currency, !currency.isEmpty else { return false }
        return true
    }

    private func createDraft(item: SMSLatestReviewMessage, result: SMSLatestReviewAIResult) {
        guard canCreateDraft(result) else {
            notice = "AI did not provide enough information to create a transaction draft."
            return
        }
        let candidate = SMSAICandidate(
            id: item.id,
            sourceKey: item.sourceKey,
            sender: item.sender,
            rowID: item.rowID,
            date: item.date,
            details: item.details,
            queuedAt: item.queuedAt
        )
        let legacy = SMSAIRecognitionResult(
            transactionType: result.transactionType,
            amount: result.amount,
            currency: result.currency,
            accountAlias: result.accountAlias,
            vendor: result.vendor,
            category: result.category,
            confidence: result.confidence,
            reason: result.reason,
            provider: result.model.map { "OpenAI · \($0)" } ?? "OpenAI"
        )
        do {
            try SMSImportConsoleService.applyAIRecovery(legacy, to: candidate)
            SMSLatest15ReviewService.setDisposition("draft", for: item.id)
            aiLog.append("Row \(item.rowID) sent to editable Drafts.")
            notice = "Created an editable SMS draft. Open SMS Drafts to review account/category and approve it."
            reload()
        } catch {
            aiLog.append("Row \(item.rowID) draft error: \(error.localizedDescription)")
            notice = "Could not create draft: \(error.localizedDescription)"
        }
    }
}
'''
write("DailyLedger/Views/SMSLatest15ReviewView.swift", review_swift)

# ---------------------------------------------------------------------------
# Console UI: latest-15 collection, finite scan display, review navigation and
# removal of the confusing legacy AI recovery block.
# ---------------------------------------------------------------------------
view = "DailyLedger/Views/SMSImportConsoleView.swift"
text = read(view)

# Replace the manual button/progress area from the generated latest-20 version.
pattern = r'''(?s)\s*Button \{\n\s*startManualScan\(\)\n\s*\} label: \{\n\s*Label\(localManualScan \|\| snapshot\.scanInProgress == true \? "Scanning Latest 20 SMS…" : "Manual Scan · Latest 20 SMS", systemImage: "arrow\.clockwise\.circle\.fill"\)\n\s*\}\n\s*\.disabled\(localManualScan \|\| snapshot\.scanInProgress == true\)\n\s*\n\s*if localManualScan \|\| snapshot\.scanInProgress == true \{.*?\n\s*\}\n'''
replacement = r'''
                Button {
                    startManualScan()
                } label: {
                    Label(effectiveManualScanActive ? "Collecting Latest 15…" : "Collect Latest 15 Messages", systemImage: "arrow.clockwise.circle.fill")
                }
                .disabled(effectiveManualScanActive)

                if effectiveManualScanActive {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: scanProgress)
                        HStack {
                            Text(snapshot.scanPhase ?? "Waiting for daemon…")
                            Spacer()
                            Text("\(scanProgressPercent)%")
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else if snapshot.scanInProgress == true {
                    Text("Previous scan status is stale. You can start a new Latest 15 scan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    SMSLatest15ReviewView()
                } label: {
                    Label("Review Latest 15 Messages (\(SMSLatest15ReviewService.load().count))", systemImage: "text.bubble.fill")
                }
'''
text, count = re.subn(pattern, replacement, text, count=1)
if count != 1:
    raise RuntimeError(f"Could not replace generated latest-20 manual scan UI, count={count}")

# Remove legacy AI recovery status/retry block introduced in 1.3.58. New review
# view owns AI status, progress and logs.
legacy_pattern = r'''(?s)\s*LabeledContent\("AI Recognition", value: OpenAIService\.shared\.hasAPIKey \? "OpenAI Connected" : "OpenAI API required"\).*?\.disabled\(!OpenAIService\.shared\.hasAPIKey \|\| SMSImportConsoleService\.loadAICandidates\(\)\.isEmpty\)\n'''
text, legacy_count = re.subn(legacy_pattern, '''
                LabeledContent("AI Helper", value: OpenAIService.shared.hasAPIKey ? "Key saved · test in Latest 15 Review" : "OpenAI API required")
''', text, count=1)
if legacy_count != 1:
    raise RuntimeError(f"Could not replace legacy AI recovery console block, count={legacy_count}")

# Add a timeout-based effective scan state so UI cannot remain permanently busy.
scan_func_anchor = '''    private var scanProgress: Double {
'''
if scan_func_anchor not in text:
    raise RuntimeError("scanProgress anchor not found")
text = text.replace(scan_func_anchor, '''    private var effectiveManualScanActive: Bool {
        if let requested = manualScanRequestedAt,
           Date().timeIntervalSince(requested) <= 25,
           localManualScan || snapshot.scanInProgress == true {
            return true
        }
        return false
    }

''' + scan_func_anchor, 1)
text = text.replace('let total = max(snapshot.scanProgressTotal ?? 20, 1)', 'let total = max(snapshot.scanProgressTotal ?? 15, 1)', 1)

# Existing completion logic plus hard timeout.
refresh_anchor = '''        if localManualScan,
           snapshot.scanInProgress != true,
           let requested = manualScanRequestedAt,
           let completed = snapshot.lastScanDate,
           completed >= requested.addingTimeInterval(-1) {
            localManualScan = false
        }
'''
if refresh_anchor in text:
    text = text.replace(refresh_anchor, refresh_anchor + '''        if localManualScan,
           let requested = manualScanRequestedAt,
           Date().timeIntervalSince(requested) > 25 {
            localManualScan = false
        }
''', 1)
else:
    raise RuntimeError("manual scan completion anchor not found")

# Wording cleanup.
text = text.replace('Manual Scan · Latest 20 SMS', 'Collect Latest 15 Messages')
text = text.replace('latest 20', 'latest 15')
write(view, text)

# Version label.
settings = "DailyLedger/Views/SettingsView.swift"
settings_text = read(settings)
settings_text = re.sub(r'LabeledContent\("Version", value: "[^"]+"\)', 'LabeledContent("Version", value: "1.3.59")', settings_text, count=1)
write(settings, settings_text)

print("Prepared Next Ledger 1.3.59 + daemon 2.2.1: deterministic latest-15 full-message review, finite manual scan, explicit user approve/reject flow, stable OpenAI SMS model, realtime AI progress/logs, and no legacy automatic AI recovery loop.")
