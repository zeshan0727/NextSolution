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
# Version bump: app 1.3.53 build 61, RootHide SMS daemon 2.2.0.
# ---------------------------------------------------------------------------
replace_once("project.yml", 'MARKETING_VERSION: "1.3.52"', 'MARKETING_VERSION: "1.3.53"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "60"', 'CURRENT_PROJECT_VERSION: "61"')

source = "RootHideSMSQueue/Sources/main.m"
replace_once(source, 'static NSString *const kDaemonVersion = @"2.1.9";', 'static NSString *const kDaemonVersion = @"2.2.0";')

# ---------------------------------------------------------------------------
# Persistent unresolved-SMS queue shared with the app.
# The daemon only queues approved-bank SMS; it never receives the OpenAI key.
# ---------------------------------------------------------------------------
replace_once(
    source,
    '''static NSString *ReviewedIDsPath(void) {
    NSString *directory = AppSupportDirectory();
    return directory ? [directory stringByAppendingPathComponent:@"sms-import-reviewed.json"] : nil;
}

static NSString *DraftLockPath(void) {
''',
    '''static NSString *ReviewedIDsPath(void) {
    NSString *directory = AppSupportDirectory();
    return directory ? [directory stringByAppendingPathComponent:@"sms-import-reviewed.json"] : nil;
}

static NSString *AICandidatesPath(void) {
    NSString *directory = AppSupportDirectory();
    return directory ? [directory stringByAppendingPathComponent:@"sms-ai-candidates.json"] : nil;
}

static NSString *AIProcessedIDsPath(void) {
    NSString *directory = AppSupportDirectory();
    return directory ? [directory stringByAppendingPathComponent:@"sms-ai-processed.json"] : nil;
}

static NSString *DraftLockPath(void) {
''',
)

# Queue once per sourceKey. The candidate ID intentionally matches the draft ID,
# so an AI-created draft and deterministic fallback draft cannot duplicate.
replace_once(
    source,
    '''static NSString *NormalizedSender(NSString *value) {
''',
    r'''static BOOL QueueAICandidate(NSString *text, NSString *sourceKey, NSString *sender, sqlite3_int64 rowID, NSDate *date) {
    if (text.length == 0 || sourceKey.length == 0) return NO;
    NSString *identifier = DeterministicUUID(sourceKey).UUIDString;
    int descriptor = AcquireDraftLock();
    if (descriptor < 0) return NO;
    BOOL queued = NO;
    @try {
        NSArray *processed = ReadJSONArray(AIProcessedIDsPath());
        if ([processed containsObject:identifier]) return NO;
        NSMutableArray *items = [ReadJSONArray(AICandidatesPath()) mutableCopy];
        for (NSDictionary *item in items) {
            if ([item[@"id"] isEqualToString:identifier] || [item[@"sourceKey"] isEqualToString:sourceKey]) {
                return NO;
            }
        }
        [items addObject:@{
            @"id": identifier,
            @"sourceKey": sourceKey,
            @"sender": sender ?: @"",
            @"rowID": @(rowID),
            @"date": ISODate(date ?: NSDate.date),
            @"details": CleanWhitespace(text),
            @"queuedAt": ISODate(NSDate.date)
        }];
        [items sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            NSNumber *leftRow = [left[@"rowID"] isKindOfClass:NSNumber.class] ? left[@"rowID"] : @0;
            NSNumber *rightRow = [right[@"rowID"] isKindOfClass:NSNumber.class] ? right[@"rowID"] : @0;
            return [rightRow compare:leftRow];
        }];
        while (items.count > 100) [items removeLastObject];
        queued = WriteJSONArray(items, AICandidatesPath());
    } @finally {
        ReleaseDraftLock(descriptor);
    }
    if (queued) {
        AddLog(@"info", @"Queued SMS row %lld for OpenAI database recovery.", rowID);
    }
    return queued;
}

static NSString *NormalizedSender(NSString *value) {
''',
)

# Unclassified readable approved-bank messages go to AI even when local fallback
# heuristics cannot decide whether they are transactional.
replace_once(
    source,
    '''            if (!parsed) {
                parseFailures += 1;
                NSString *preview = text.length > 160 ? [[text substringToIndex:160] stringByAppendingString:@"…"] : text;
                AddLog(@"warning", @"Approved-bank SMS row %lld was not classified and did not look transactional: %@", rowID, preview);
                continue;
            }
''',
    '''            if (!parsed) {
                parseFailures += 1;
                const unsigned char *guidBytesForAI = sqlite3_column_text(statement, 1);
                NSString *guidForAI = guidBytesForAI ? [NSString stringWithUTF8String:(const char *)guidBytesForAI] : @"";
                NSString *sourceForAI = guidForAI.length ? guidForAI : [NSString stringWithFormat:@"%lld|%@", rowID, text];
                QueueAICandidate(text, sourceForAI, sender, rowID, DatabaseDate(sqlite3_column_int64(statement, 4)));
                NSString *preview = text.length > 160 ? [[text substringToIndex:160] stringByAppendingString:@"…"] : text;
                AddLog(@"warning", @"Approved-bank SMS row %lld was not classified locally; queued for OpenAI recovery: %@", rowID, preview);
                continue;
            }
''',
)

# Locally recognized review-fallback transactions are also sent to AI so AI can
# enrich type/vendor/category/account hints while preserving a guaranteed draft.
replace_once(
    source,
    '''            reviewFallback = YES;
            reviewFallbacks += 1;
            AddLog(@"info", @"SMS row %lld could not be classified confidently; created a manual-review candidate (%@).", rowID, parsed[@"kind"]);
''',
    '''            reviewFallback = YES;
            reviewFallbacks += 1;
            const unsigned char *guidBytesForAI = sqlite3_column_text(statement, 1);
            NSString *guidForAI = guidBytesForAI ? [NSString stringWithUTF8String:(const char *)guidBytesForAI] : @"";
            NSString *sourceForAI = guidForAI.length ? guidForAI : [NSString stringWithFormat:@"%lld|%@", rowID, text];
            QueueAICandidate(text, sourceForAI, sender, rowID, DatabaseDate(sqlite3_column_int64(statement, 4)));
            AddLog(@"info", @"SMS row %lld could not be classified confidently; created a manual-review candidate (%@) and queued OpenAI enrichment.", rowID, parsed[@"kind"]);
''',
)

# Show queue depth in the app console snapshot.
replace_once(
    source,
    '''        @"pendingCount": @(PendingCount()),
        @"scanInProgress": gState[@"scanInProgress"] ?: @NO,
''',
    '''        @"pendingCount": @(PendingCount()),
        @"aiCandidateCount": @(ReadJSONArray(AICandidatesPath()).count),
        @"scanInProgress": gState[@"scanInProgress"] ?: @NO,
''',
)

# ---------------------------------------------------------------------------
# Swift service: decode queue, atomically complete candidates, and merge AI
# classifications into editable drafts using the same draft lock.
# ---------------------------------------------------------------------------
service = "DailyLedger/Services/SMSImportConsoleService.swift"
replace_once(
    service,
    '''struct SMSImportLogEntry: Codable, Identifiable, Equatable {
''',
    '''struct SMSAICandidate: Codable, Identifiable, Equatable {
    let id: UUID
    let sourceKey: String
    let sender: String
    let rowID: Int64
    let date: Date
    let details: String
    let queuedAt: Date
}

struct SMSImportLogEntry: Codable, Identifiable, Equatable {
''',
)

replace_once(
    service,
    '''    var scanProgressTotal: Int?
    var scanPhase: String?
    var logs: [SMSImportLogEntry] = []
''',
    '''    var scanProgressTotal: Int?
    var scanPhase: String?
    var aiCandidateCount: Int?
    var logs: [SMSImportLogEntry] = []
''',
)

replace_once(
    service,
    '''    static var reviewedURL: URL {
        directoryURL.appendingPathComponent("sms-import-reviewed.json")
    }
''',
    '''    static var reviewedURL: URL {
        directoryURL.appendingPathComponent("sms-import-reviewed.json")
    }

    static var aiCandidatesURL: URL {
        directoryURL.appendingPathComponent("sms-ai-candidates.json")
    }

    static var aiProcessedURL: URL {
        directoryURL.appendingPathComponent("sms-ai-processed.json")
    }
''',
)

replace_once(
    service,
    '''    static func loadDrafts() -> [SMSImportDraft] {
''',
    '''    static func loadAICandidates() -> [SMSAICandidate] {
        (try? withDraftLock {
            guard let data = try? Data(contentsOf: aiCandidatesURL) else { return [] }
            return (try? decoder.decode([SMSAICandidate].self, from: data)) ?? []
        }) ?? []
    }

    static func completeAICandidate(_ candidate: SMSAICandidate) throws {
        try withDraftLock {
            var candidates: [SMSAICandidate] = []
            if let data = try? Data(contentsOf: aiCandidatesURL) {
                candidates = (try? decoder.decode([SMSAICandidate].self, from: data)) ?? []
            }
            candidates.removeAll { $0.id == candidate.id }
            try encoder.encode(candidates).write(to: aiCandidatesURL, options: .atomic)

            var processed: [String] = []
            if let data = try? Data(contentsOf: aiProcessedURL) {
                processed = (try? JSONDecoder().decode([String].self, from: data)) ?? []
            }
            if !processed.contains(candidate.id.uuidString) { processed.append(candidate.id.uuidString) }
            if processed.count > 10_000 { processed.removeFirst(processed.count - 10_000) }
            try JSONEncoder().encode(processed).write(to: aiProcessedURL, options: .atomic)
        }
    }

    static func applyAIRecovery(_ result: SMSAIRecognitionResult, to candidate: SMSAICandidate) throws {
        guard result.transactionType != "ignore" else {
            try completeAICandidate(candidate)
            return
        }
        guard let rawAmount = result.amount?.replacingOccurrences(of: ",", with: ""),
              let amount = Decimal(string: rawAmount), amount > 0,
              let currency = result.currency?.trimmingCharacters(in: .whitespacesAndNewlines),
              !currency.isEmpty else {
            throw SMSAIRecognitionError.invalidResponse
        }

        let kind: String
        switch result.transactionType {
        case "income": kind = "reviewIncome"
        case "transfer": kind = "reviewTransfer"
        default: kind = "reviewExpense"
        }
        let alias = result.accountAlias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let vendor = result.vendor?.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = SMSImportDraft(
            id: candidate.id,
            sourceKey: candidate.sourceKey,
            sender: candidate.sender,
            rowID: candidate.rowID,
            kind: kind,
            currency: currency.uppercased() == "QR" ? "QAR" : currency.uppercased(),
            amount: amount,
            cardEnding: alias.uppercased(),
            vendor: (vendor?.isEmpty == false ? vendor! : "AI Review"),
            date: candidate.date,
            details: candidate.details,
            queuedAt: candidate.queuedAt
        )

        try withDraftLock {
            var drafts: [SMSImportDraft] = []
            if let data = try? Data(contentsOf: draftsURL) {
                drafts = (try? decoder.decode([SMSImportDraft].self, from: data)) ?? []
            }
            drafts.removeAll { $0.id == candidate.id || $0.sourceKey == candidate.sourceKey }
            drafts.append(replacement)
            drafts.sort { $0.rowID > $1.rowID }
            try encoder.encode(drafts).write(to: draftsURL, options: .atomic)

            var candidates: [SMSAICandidate] = []
            if let data = try? Data(contentsOf: aiCandidatesURL) {
                candidates = (try? decoder.decode([SMSAICandidate].self, from: data)) ?? []
            }
            candidates.removeAll { $0.id == candidate.id }
            try encoder.encode(candidates).write(to: aiCandidatesURL, options: .atomic)

            var processed: [String] = []
            if let data = try? Data(contentsOf: aiProcessedURL) {
                processed = (try? JSONDecoder().decode([String].self, from: data)) ?? []
            }
            if !processed.contains(candidate.id.uuidString) { processed.append(candidate.id.uuidString) }
            if processed.count > 10_000 { processed.removeFirst(processed.count - 10_000) }
            try JSONEncoder().encode(processed).write(to: aiProcessedURL, options: .atomic)
        }
    }

    static func loadDrafts() -> [SMSImportDraft] {
''',
)

# ---------------------------------------------------------------------------
# AI recognizer: database candidates use the same secure OpenAI request path.
# Allow "ignore" so OTP/balance/service alerts never become fake transactions.
# ---------------------------------------------------------------------------
ai = "DailyLedger/Services/SMSAIRecognitionService.swift"
replace_once(
    ai,
    '''        You classify one bank SMS for a personal ledger. Return JSON only. Never invent an account, beneficiary, amount, currency, date, or direction that the SMS does not support. transactionType must be income, expense, or transfer. Use transfer for card payments between the user's own bank/current/card accounts, cash withdrawals, remittances between accounts, or explicit transfers. Confidence must be 0 to 1. Keep vendor and category short.
''',
    '''        You classify one bank SMS for a personal ledger. Return JSON only. Never invent an account, beneficiary, amount, currency, date, or direction that the SMS does not support. transactionType must be income, expense, transfer, or ignore. Use ignore for OTPs, login/security alerts, balance-only notifications, marketing, service messages, failed/declined transactions without an actual posted movement, and anything that is not a real ledger movement. Use transfer for card payments between the user's own bank/current/card accounts, cash withdrawals, remittances between accounts, or explicit transfers. Confidence must be 0 to 1. Keep vendor and category short.
''',
)
replace_once(
    ai,
    '''        {"transactionType":"income|expense|transfer","amount":"number or null","currency":"code or null","accountAlias":"source alias/card ending if stated or null","vendor":"counterparty/purpose or null","category":"short category","confidence":0.0,"reason":"short reason"}
''',
    '''        {"transactionType":"income|expense|transfer|ignore","amount":"number or null","currency":"code or null","accountAlias":"source alias/card ending if stated or null","vendor":"counterparty/purpose or null","category":"short category or null","confidence":0.0,"reason":"short reason"}
''',
)
replace_once(
    ai,
    '''        let allowed = ["income", "expense", "transfer"]
''',
    '''        let allowed = ["income", "expense", "transfer", "ignore"]
''',
)
replace_once(
    ai,
    '''    static func clearCache(for id: UUID) {
''',
    '''    static func analyze(candidate: SMSAICandidate) async throws -> SMSAIRecognitionResult {
        let temporary = SMSImportDraft(
            id: candidate.id,
            sourceKey: candidate.sourceKey,
            sender: candidate.sender,
            rowID: candidate.rowID,
            kind: "reviewTransaction",
            currency: "",
            amount: 0,
            cardEnding: "",
            vendor: "AI Database Recovery",
            date: candidate.date,
            details: candidate.details,
            queuedAt: candidate.queuedAt
        )
        return try await analyze(draft: temporary)
    }

    static func clearCache(for id: UUID) {
''',
)

# A manual draft should not be rewritten as an expense if AI correctly returns ignore.
inbox = "DailyLedger/Views/SMSDraftInboxView.swift"
replace_once(
    inbox,
    '''    private func applyAIRecognition(_ result: SMSAIRecognitionResult) {
        switch result.transactionType {
''',
    '''    private func applyAIRecognition(_ result: SMSAIRecognitionResult) {
        if result.transactionType == "ignore" {
            let confidence = Int((result.confidence * 100).rounded())
            aiRecognitionNote = "\\(result.provider ?? \"AI\") says this is not a ledger transaction (\\(confidence)% confidence)."
            return
        }
        switch result.transactionType {
''',
)

# ---------------------------------------------------------------------------
# Realtime app coordinator: candidate queue is always processed before ordinary
# draft enrichment. OpenAI key stays in Keychain; failures stay queued for retry.
# ---------------------------------------------------------------------------
console = "DailyLedger/Views/SMSImportConsoleView.swift"
replace_once(
    console,
    '''    private func startAIRecognitionIfNeeded() {
        guard aiRecognitionEnabled, !aiProcessing, SMSAIRecognitionService.isAvailable else { return }
        let drafts = SMSImportConsoleService.loadDrafts().filter {
            $0.kind.hasPrefix("review") && SMSAIRecognitionService.cachedResult(for: $0.id) == nil
        }
        guard !drafts.isEmpty else { return }
        aiProcessing = true
        Task {
            var completed = 0
            for draft in drafts.prefix(20) {
                do {
                    _ = try await SMSAIRecognitionService.analyze(draft: draft)
                    completed += 1
                } catch {
                    SMSAIRecognitionService.recordFailure(error)
                }
            }
            await MainActor.run {
                aiProcessedCount += completed
                aiProcessing = false
            }
        }
    }
''',
    '''    private func startAIRecognitionIfNeeded() {
        guard aiRecognitionEnabled, !aiProcessing, SMSAIRecognitionService.isAvailable else { return }
        let databaseCandidates = SMSImportConsoleService.loadAICandidates()
        let drafts = SMSImportConsoleService.loadDrafts().filter {
            $0.kind.hasPrefix("review") && SMSAIRecognitionService.cachedResult(for: $0.id) == nil
        }
        guard !databaseCandidates.isEmpty || !drafts.isEmpty else { return }
        aiProcessing = true
        Task {
            var completed = 0

            // Database recovery is highest priority. One source row is sent once;
            // successful ignore/transaction results are marked processed atomically.
            for candidate in databaseCandidates.prefix(10) {
                do {
                    let result = try await SMSAIRecognitionService.analyze(candidate: candidate)
                    try SMSImportConsoleService.applyAIRecovery(result, to: candidate)
                    completed += 1
                } catch {
                    SMSAIRecognitionService.recordFailure(error)
                    // Keep the candidate queued so a network/API failure can retry.
                    break
                }
            }

            // Refresh after recovery so newly created AI drafts are not immediately
            // sent through a redundant second request.
            let remainingDrafts = SMSImportConsoleService.loadDrafts().filter {
                $0.kind.hasPrefix("review") && SMSAIRecognitionService.cachedResult(for: $0.id) == nil
            }
            for draft in remainingDrafts.prefix(10) {
                do {
                    _ = try await SMSAIRecognitionService.analyze(draft: draft)
                    completed += 1
                } catch {
                    SMSAIRecognitionService.recordFailure(error)
                    break
                }
            }
            await MainActor.run {
                aiProcessedCount += completed
                aiProcessing = false
                refresh()
            }
        }
    }
''',
)

replace_once(
    console,
    '''                Text("When enabled, only SMS that the local parser cannot classify confidently is sent to your configured OpenAI or DeepSeek account. AI results remain review suggestions; they are not blindly recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
''',
    '''                Text("Realtime recovery: the SMS daemon queues approved-bank messages the local parser misses. Next Ledger sends those unresolved messages to OpenAI, then places valid Income / Expense / Transfer results into editable Drafts. OTPs and non-transaction alerts can be ignored by AI. The API key never leaves the app's secure Keychain except as the normal Authorization header to OpenAI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Database AI Queue", value: "\\(snapshot.aiCandidateCount ?? SMSImportConsoleService.loadAICandidates().count)")
                LabeledContent("OpenAI API", value: OpenAIService.shared.hasAPIKey ? "Connected" : "API key required")
''',
)

# Status page test now tests the raw database queue first, proving database->AI.
replace_once(
    console,
    '''        let drafts = SMSImportConsoleService.loadDrafts().filter { $0.kind.hasPrefix("review") }
        guard let draft = drafts.first else {
            message = "No unresolved review draft is available. Run Manual Scan first."
            return
        }
        testing = true
        defer { testing = false }
        do {
            SMSAIRecognitionService.clearCache(for: draft.id)
            let result = try await SMSAIRecognitionService.analyze(draft: draft)
            message = "Verified \\(result.provider ?? \"AI\"): \\(result.transactionType.capitalized), \\(Int((result.confidence * 100).rounded()))% confidence."
            refreshToken = UUID()
''',
    '''        let candidates = SMSImportConsoleService.loadAICandidates()
        let drafts = SMSImportConsoleService.loadDrafts().filter { $0.kind.hasPrefix("review") }
        guard let candidate = candidates.first ?? drafts.first.map({ draft in
            SMSAICandidate(id: draft.id, sourceKey: draft.sourceKey, sender: draft.sender, rowID: draft.rowID, date: draft.date, details: draft.details, queuedAt: draft.queuedAt)
        }) else {
            message = "No unresolved database SMS is available. Run Manual Scan first."
            return
        }
        testing = true
        defer { testing = false }
        do {
            SMSAIRecognitionService.clearCache(for: candidate.id)
            let result = try await SMSAIRecognitionService.analyze(candidate: candidate)
            message = "Verified database → \\(result.provider ?? \"AI\"): \\(result.transactionType.capitalized), \\(Int((result.confidence * 100).rounded()))% confidence. Test does not record or remove the queue item."
            refreshToken = UUID()
''',
)

# Package metadata.
replace_once("RootHideSMSQueue/control", "Version: 2.1.9", "Version: 2.2.0")
for path in ["RootHideSMSQueue/postinst", "RootHideSMSQueue/layout/DEBIAN/postinst"]:
    replace_once(
        path,
        "Next Ledger SMS Daemon 2.1.9 installation started",
        "Next Ledger SMS Daemon 2.2.0 installation started",
    )

print("Prepared Next Ledger 1.3.53: realtime Messages DB -> OpenAI -> editable Draft recovery with dedupe and secure app-side API calls.")
