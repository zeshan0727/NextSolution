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
        raise RuntimeError(f"Expected one match in {path}, found {count}: {old[:180]!r}")
    write(path, text.replace(old, new, 1))


def replace_exact_count(path: str, old: str, new: str, expected: int) -> None:
    text = read(path)
    count = text.count(old)
    if count != expected:
        raise RuntimeError(f"Expected {expected} matches in {path}, found {count}: {old[:180]!r}")
    write(path, text.replace(old, new))


source = "RootHideSMSQueue/Sources/main.m"
replace_once(source, 'static NSString *const kDaemonVersion = @"2.0.3";', 'static NSString *const kDaemonVersion = @"2.1.0";')

replace_once(
    source,
    '''static NSDictionary *LoadConfiguration(void) {
    NSDictionary *config = ReadJSON(ConfigurationPath());
    return config ?: @{
        @"enabled": @YES,
        @"cardAccountIDs": @{},
        @"scanRequestID": @0
    };
}

static NSInteger PendingCount(void) {
    EnsureDirectory(PendingDirectory());
    return [NSFileManager.defaultManager contentsOfDirectoryAtPath:PendingDirectory() error:nil].count;
}
''',
    '''static NSString *DraftsPath(void) {
    NSString *directory = AppSupportDirectory();
    return directory ? [directory stringByAppendingPathComponent:@"sms-import-drafts.json"] : nil;
}

static NSString *ReviewedIDsPath(void) {
    NSString *directory = AppSupportDirectory();
    return directory ? [directory stringByAppendingPathComponent:@"sms-import-reviewed.json"] : nil;
}

static NSString *DraftLockPath(void) {
    NSString *directory = AppSupportDirectory();
    return directory ? [directory stringByAppendingPathComponent:@"sms-import-drafts.lock"] : nil;
}

static NSArray *ReadJSONArray(NSString *path) {
    NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
    if (!data) return @[];
    id value = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    return [value isKindOfClass:NSArray.class] ? value : @[];
}

static BOOL WriteJSONArray(NSArray *array, NSString *path) {
    if (!path || ![NSJSONSerialization isValidJSONObject:array]) return NO;
    EnsureDirectory(path.stringByDeletingLastPathComponent);
    NSData *data = [NSJSONSerialization dataWithJSONObject:array
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:nil];
    return data && [data writeToFile:path options:NSDataWritingAtomic error:nil];
}

static int AcquireDraftLock(void) {
    NSString *path = DraftLockPath();
    if (!path) return -1;
    EnsureDirectory(path.stringByDeletingLastPathComponent);
    int descriptor = open(path.fileSystemRepresentation, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR);
    if (descriptor < 0) return -1;
    struct flock lock = {.l_type = F_WRLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 0};
    if (fcntl(descriptor, F_SETLKW, &lock) != 0) {
        close(descriptor);
        return -1;
    }
    return descriptor;
}

static void ReleaseDraftLock(int descriptor) {
    if (descriptor < 0) return;
    struct flock lock = {.l_type = F_UNLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 0};
    fcntl(descriptor, F_SETLK, &lock);
    close(descriptor);
}

static NSDictionary *LoadConfiguration(void) {
    NSDictionary *config = ReadJSON(ConfigurationPath());
    return config ?: @{
        @"enabled": @YES,
        @"cardAccountIDs": @{},
        @"approvedSenders": @[@"Cb SMS"],
        @"scanRequestID": @0
    };
}

static NSInteger PendingCount(void) {
    return ReadJSONArray(DraftsPath()).count;
}
''',
)

replace_once(
    source,
    '''static NSString *QueueEvent(NSDictionary *parsed, NSString *sourceKey, NSString *sender) {
''',
    '''static NSString *NormalizedSender(NSString *value) {
    NSString *lower = value.lowercaseString ?: @"";
    NSMutableString *result = [NSMutableString string];
    NSCharacterSet *allowed = NSCharacterSet.alphanumericCharacterSet;
    for (NSUInteger index = 0; index < lower.length; index++) {
        unichar character = [lower characterAtIndex:index];
        if ([allowed characterIsMember:character]) [result appendFormat:@"%C", character];
    }
    return result;
}

static BOOL SenderApproved(NSDictionary *config, NSString *sender) {
    NSArray *approved = [config[@"approvedSenders"] isKindOfClass:NSArray.class]
        ? config[@"approvedSenders"] : @[@"Cb SMS"];
    NSString *candidate = NormalizedSender(sender);
    if (candidate.length == 0) return NO;
    for (NSString *item in approved) {
        NSString *needle = NormalizedSender(item);
        if (needle.length > 0 && ([candidate isEqualToString:needle] || [candidate containsString:needle] || [needle containsString:candidate])) {
            return YES;
        }
    }
    return NO;
}

static BOOL CardEndingApproved(NSDictionary *config, NSString *ending) {
    NSDictionary *mappings = [config[@"cardAccountIDs"] isKindOfClass:NSDictionary.class]
        ? config[@"cardAccountIDs"] : @{};
    if (mappings.count > 0) return mappings[ending] != nil;
    return [@[@"6760", @"0023"] containsObject:ending];
}

typedef NS_ENUM(NSInteger, DraftResult) {
    DraftResultCreated = 1,
    DraftResultAlreadyPending = 2,
    DraftResultAlreadyReviewed = 3,
    DraftResultFailed = 4
};

static DraftResult CreateDraft(NSDictionary *parsed, NSString *sourceKey, NSString *sender, sqlite3_int64 rowID) {
    NSString *identifier = DeterministicUUID(sourceKey).UUIDString;
    int descriptor = AcquireDraftLock();
    if (descriptor < 0) return DraftResultFailed;
    DraftResult result = DraftResultFailed;
    @try {
        NSArray *reviewed = ReadJSONArray(ReviewedIDsPath());
        if ([reviewed containsObject:identifier]) {
            result = DraftResultAlreadyReviewed;
            return result;
        }
        NSMutableArray *drafts = [ReadJSONArray(DraftsPath()) mutableCopy];
        for (NSDictionary *draft in drafts) {
            if ([draft[@"id"] isEqualToString:identifier]) {
                result = DraftResultAlreadyPending;
                return result;
            }
        }
        NSMutableDictionary *draft = [parsed mutableCopy];
        draft[@"id"] = identifier;
        draft[@"sourceKey"] = sourceKey;
        draft[@"sender"] = sender ?: @"";
        draft[@"rowID"] = @(rowID);
        draft[@"queuedAt"] = ISODate(NSDate.date);
        [drafts addObject:draft];
        [drafts sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            return [right[@"rowID"] compare:left[@"rowID"]];
        }];
        result = WriteJSONArray(drafts, DraftsPath()) ? DraftResultCreated : DraftResultFailed;
    } @finally {
        ReleaseDraftLock(descriptor);
    }
    if (result == DraftResultCreated) {
        AddLog(@"info", @"Created approval draft for %@ %@ %@ from **%@ (%@).",
            parsed[@"kind"], parsed[@"currency"], parsed[@"amount"], parsed[@"cardEnding"], sender ?: @"unknown sender");
    }
    return result;
}

static NSString *QueueEvent(NSDictionary *parsed, NSString *sourceKey, NSString *sender) {
''',
)

replace_exact_count(source, '    RetryPending(config);\n', '', 2)
replace_once(
    source,
    '''        "AND (m.text IS NOT NULL OR m.attributedBody IS NOT NULL) ORDER BY m.ROWID ASC";
''',
    '''        "AND (m.text IS NOT NULL OR m.attributedBody IS NOT NULL) ORDER BY m.ROWID DESC";
''',
)

replace_once(
    source,
    '''    NSInteger inspected = 0;
    NSInteger matched = 0;
    NSInteger parseFailures = 0;
    while (sqlite3_step(statement) == SQLITE_ROW) {
        inspected += 1;
        sqlite3_int64 rowID = sqlite3_column_int64(statement, 0);
        NSString *text = MessageText(statement);
        if (text.length == 0) continue;
        NSDictionary *parsed = ParseTransaction(text, DatabaseDate(sqlite3_column_int64(statement, 4)));
        if (!parsed) {
            NSString *lower = text.lowercaseString;
            if ([lower containsString:@"**6760"] || [lower containsString:@"**0023"] || [lower containsString:@"bill payment"] || [lower containsString:@"cashback"]) {
                parseFailures += 1;
                AddLog(@"warning", @"SMS row %lld looked like a bank message but could not be classified.", rowID);
            }
            continue;
        }
        matched += 1;
        const unsigned char *guidBytes = sqlite3_column_text(statement, 1);
        const unsigned char *senderBytes = sqlite3_column_text(statement, 5);
        NSString *guid = guidBytes ? [NSString stringWithUTF8String:(const char *)guidBytes] : @"";
        NSString *sender = senderBytes ? [NSString stringWithUTF8String:(const char *)senderBytes] : @"";
        NSString *source = guid.length ? guid : [NSString stringWithFormat:@"%lld|%@", rowID, text];
        QueueEvent(parsed, source, sender);
    }
''',
    '''    NSInteger inspected = 0;
    NSInteger matched = 0;
    NSInteger draftsCreated = 0;
    NSInteger alreadyHandled = 0;
    NSInteger ignoredSender = 0;
    NSInteger ignoredCard = 0;
    NSInteger parseFailures = 0;
    while (sqlite3_step(statement) == SQLITE_ROW) {
        inspected += 1;
        sqlite3_int64 rowID = sqlite3_column_int64(statement, 0);
        const unsigned char *senderBytes = sqlite3_column_text(statement, 5);
        NSString *sender = senderBytes ? [NSString stringWithUTF8String:(const char *)senderBytes] : @"";
        if (!SenderApproved(config, sender)) {
            ignoredSender += 1;
            continue;
        }

        NSString *text = MessageText(statement);
        if (text.length == 0) continue;
        NSDictionary *parsed = ParseTransaction(text, DatabaseDate(sqlite3_column_int64(statement, 4)));
        if (!parsed) {
            NSString *lower = text.lowercaseString;
            if ([lower containsString:@"used for"] || [lower containsString:@"bill payment"] || [lower containsString:@"cashback"] || [lower containsString:@"withdrawal"] || [lower containsString:@"credited"]) {
                parseFailures += 1;
                AddLog(@"warning", @"Approved-bank SMS row %lld could not be classified.", rowID);
            }
            continue;
        }
        if (!CardEndingApproved(config, parsed[@"cardEnding"])) {
            ignoredCard += 1;
            continue;
        }

        matched += 1;
        const unsigned char *guidBytes = sqlite3_column_text(statement, 1);
        NSString *guid = guidBytes ? [NSString stringWithUTF8String:(const char *)guidBytes] : @"";
        NSString *source = guid.length ? guid : [NSString stringWithFormat:@"%lld|%@", rowID, text];
        DraftResult draftResult = CreateDraft(parsed, source, sender, rowID);
        if (draftResult == DraftResultCreated) draftsCreated += 1;
        else if (draftResult == DraftResultAlreadyPending || draftResult == DraftResultAlreadyReviewed) alreadyHandled += 1;
        else AddLog(@"error", @"Could not save approval draft for SMS row %lld.", rowID);
    }
''',
)

replace_once(
    source,
    '''    NSString *result = [NSString stringWithFormat:@"Inspected %ld new/recent messages, classified %ld bank transaction%@, parse failures %ld.",
        (long)inspected, (long)matched, matched == 1 ? @"" : @"s", (long)parseFailures];
''',
    '''    NSString *result = [NSString stringWithFormat:@"Checked %ld unrecorded/new message%@ newest first; matched %ld approved bank transaction%@; created %ld draft%@; already handled %ld; ignored sender %ld; ignored card %ld; parse failures %ld.",
        (long)inspected, inspected == 1 ? @"" : @"s",
        (long)matched, matched == 1 ? @"" : @"s",
        (long)draftsCreated, draftsCreated == 1 ? @"" : @"s",
        (long)alreadyHandled, (long)ignoredSender, (long)ignoredCard, (long)parseFailures];
''',
)

service = "DailyLedger/Services/SMSImportConsoleService.swift"
replace_once(service, 'import Foundation\n', 'import Darwin\nimport Foundation\n')
replace_once(
    service,
    '''    var loanPaymentAccountID: String?
    var scanRequestID = 0
}

struct SMSImportLogEntry: Codable, Identifiable, Equatable {
''',
    '''    var loanPaymentAccountID: String?
    var approvedSenders: [String] = ["Cb SMS"]
    var scanRequestID = 0
}

struct SMSImportDraft: Codable, Identifiable, Equatable {
    let id: UUID
    let sourceKey: String
    let sender: String
    let rowID: Int64
    let kind: String
    let currency: String
    let amount: Decimal
    let cardEnding: String
    let vendor: String
    let date: Date
    let details: String
    let queuedAt: Date

    var suggestedNature: String {
        switch kind {
        case "cashback": return "Refund Income"
        case "income": return "Income"
        case "withdrawal": return "Transfer to Cash"
        case "billPayment": return "Loan Payment Transfer"
        default: return "Expense"
        }
    }
}

struct SMSImportLogEntry: Codable, Identifiable, Equatable {
''',
)

replace_once(
    service,
    '''    static func loadInstallerDiagnostic() -> String {
        (try? String(contentsOf: installerDiagnosticURL, encoding: .utf8)) ?? ""
    }

    static var directoryURL: URL {
''',
    '''    static func loadInstallerDiagnostic() -> String {
        (try? String(contentsOf: installerDiagnosticURL, encoding: .utf8)) ?? ""
    }

    static func loadDrafts() -> [SMSImportDraft] {
        (try? withDraftLock {
            guard let data = try? Data(contentsOf: draftsURL) else { return [] }
            return (try? decoder.decode([SMSImportDraft].self, from: data)) ?? []
        }) ?? []
    }

    static func completeDraft(_ draft: SMSImportDraft) throws {
        try withDraftLock {
            var drafts: [SMSImportDraft] = []
            if let data = try? Data(contentsOf: draftsURL) {
                drafts = (try? decoder.decode([SMSImportDraft].self, from: data)) ?? []
            }
            drafts.removeAll { $0.id == draft.id }
            try encoder.encode(drafts).write(to: draftsURL, options: .atomic)

            var reviewed: [String] = []
            if let data = try? Data(contentsOf: reviewedURL) {
                reviewed = (try? JSONDecoder().decode([String].self, from: data)) ?? []
            }
            if !reviewed.contains(draft.id.uuidString) {
                reviewed.append(draft.id.uuidString)
            }
            if reviewed.count > 10_000 {
                reviewed.removeFirst(reviewed.count - 10_000)
            }
            try JSONEncoder().encode(reviewed).write(to: reviewedURL, options: .atomic)
        }
    }

    private static func withDraftLock<T>(_ work: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return try work() }
        defer {
            flock(descriptor, LOCK_UN)
            Darwin.close(descriptor)
        }
        guard flock(descriptor, LOCK_EX) == 0 else { return try work() }
        return try work()
    }

    static var directoryURL: URL {
''',
)

replace_once(
    service,
    '''    static var installerDiagnosticURL: URL {
        directoryURL.appendingPathComponent("sms-import-install.log")
    }
''',
    '''    static var installerDiagnosticURL: URL {
        directoryURL.appendingPathComponent("sms-import-install.log")
    }

    static var draftsURL: URL {
        directoryURL.appendingPathComponent("sms-import-drafts.json")
    }

    static var reviewedURL: URL {
        directoryURL.appendingPathComponent("sms-import-reviewed.json")
    }

    static var lockURL: URL {
        directoryURL.appendingPathComponent("sms-import-drafts.lock")
    }
''',
)

view = "DailyLedger/Views/SMSImportConsoleView.swift"
replace_once(
    view,
    '''    @State private var installerDiagnostic = ""
    @State private var notice: String?
''',
    '''    @State private var installerDiagnostic = ""
    @State private var approvedSendersText = "Cb SMS"
    @State private var draftCount = 0
    @State private var notice: String?
''',
)
replace_once(
    view,
    '''                accountPicker(
                    title: "Loan Payment Account",
                    selection: optionalBinding(
                        get: { configuration.loanPaymentAccountID },
                        set: { configuration.loanPaymentAccountID = $0 }
                    ),
                    suggestedWords: ["loan", "payment"]
                )

                Button {
''',
    '''                accountPicker(
                    title: "Loan Payment Account",
                    selection: optionalBinding(
                        get: { configuration.loanPaymentAccountID },
                        set: { configuration.loanPaymentAccountID = $0 }
                    ),
                    suggestedWords: ["loan", "payment"]
                )

                TextField("Approved senders, comma separated", text: $approvedSendersText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                NavigationLink {
                    SMSDraftInboxView()
                } label: {
                    HStack {
                        Label("SMS Drafts", systemImage: "tray.full.fill")
                        Spacer()
                        Text("\\(draftCount)")
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
''',
)
replace_once(
    view,
    '''                    Label("Scan Recent Messages", systemImage: "arrow.clockwise.circle.fill")
''',
    '''                    Label("Find Unrecorded Recent SMS", systemImage: "arrow.clockwise.circle.fill")
''',
)
replace_once(
    view,
    '''                Text("**6760 purchases become expenses, cashback becomes refund income, **0023 withdrawals transfer to Cash, and bill payments transfer to the Loan Payment account.")
''',
    '''                Text("Only new or never-reviewed SMS from approved senders and mapped card endings become drafts. Nothing is written to the ledger until you approve it. Rejected and approved SMS cannot return.")
''',
)
replace_once(
    view,
    '''            configuration = SMSImportConsoleService.loadConfiguration()
            applySuggestedMappings()
            refresh()
''',
    '''            configuration = SMSImportConsoleService.loadConfiguration()
            approvedSendersText = configuration.approvedSenders.joined(separator: ", ")
            applySuggestedMappings()
            refresh()
''',
)
replace_once(
    view,
    '''    private func saveConfiguration(requestScan: Bool) {
        if requestScan { configuration.scanRequestID += 1 }
''',
    '''    private func saveConfiguration(requestScan: Bool) {
        configuration.approvedSenders = approvedSendersText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if configuration.approvedSenders.isEmpty { configuration.approvedSenders = ["Cb SMS"] }
        if requestScan { configuration.scanRequestID += 1 }
''',
)
replace_once(
    view,
    '''        snapshot = SMSImportConsoleService.loadSnapshot()
        installerDiagnostic = SMSImportConsoleService.loadInstallerDiagnostic()
''',
    '''        snapshot = SMSImportConsoleService.loadSnapshot()
        installerDiagnostic = SMSImportConsoleService.loadInstallerDiagnostic()
        draftCount = SMSImportConsoleService.loadDrafts().count
''',
)

store = "DailyLedger/Services/LedgerStore.swift"
replace_once(
    store,
    '''    func addAccount(_ account: LedgerAccount) {
''',
    '''    @discardableResult
    func approveSMSDraft(_ draft: SMSImportDraft, configuration: SMSImportConfiguration) -> Bool {
        if transactions.contains(where: { $0.id == draft.id }) { return true }
        guard let sourceText = configuration.cardAccountIDs[draft.cardEnding],
              let sourceID = UUID(uuidString: sourceText),
              accountsByID[sourceID] != nil else {
            errorMessage = "Map card **\\(draft.cardEnding) to an account before approval."
            return false
        }

        let item: LedgerTransaction
        switch draft.kind {
        case "withdrawal", "billPayment":
            let destinationText = draft.kind == "withdrawal"
                ? configuration.cashAccountID
                : configuration.loanPaymentAccountID
            guard let destinationText,
                  let destinationID = UUID(uuidString: destinationText),
                  accountsByID[destinationID] != nil,
                  destinationID != sourceID else {
                errorMessage = draft.kind == "withdrawal"
                    ? "Choose a valid Cash destination account."
                    : "Choose a valid Loan Payment destination account."
                return false
            }
            item = LedgerTransaction(
                id: draft.id,
                type: .transfer,
                amount: draft.amount,
                date: draft.date,
                category: "Transfer",
                vendor: draft.vendor,
                details: draft.details,
                accountID: sourceID,
                destinationAccountID: destinationID,
                destinationAmount: draft.amount
            )
        case "cashback":
            item = LedgerTransaction(
                id: draft.id,
                type: .income,
                amount: draft.amount,
                date: draft.date,
                category: "Refund",
                vendor: draft.vendor,
                details: draft.details,
                accountID: sourceID
            )
        case "income":
            item = LedgerTransaction(
                id: draft.id,
                type: .income,
                amount: draft.amount,
                date: draft.date,
                category: "Other",
                vendor: draft.vendor,
                details: draft.details,
                accountID: sourceID
            )
        default:
            let probe = LedgerTransaction(
                id: draft.id,
                type: .expense,
                amount: draft.amount,
                date: draft.date,
                category: "Other",
                vendor: draft.vendor,
                details: draft.details,
                accountID: sourceID
            )
            item = LedgerTransaction(
                id: draft.id,
                type: .expense,
                amount: draft.amount,
                date: draft.date,
                category: suggestedCategory(for: probe) ?? "Other",
                vendor: draft.vendor,
                details: draft.details,
                accountID: sourceID
            )
        }

        do {
            let ledger = try LedgerDiskStore.shared.mutate { ledger in
                guard !ledger.transactions.contains(where: { $0.id == item.id }) else { return }
                ledger.transactions.append(item)
            }
            apply(ledger)
            return true
        } catch {
            errorMessage = "The approved SMS draft could not be recorded."
            return false
        }
    }

    func addAccount(_ account: LedgerAccount) {
''',
)

inbox = r'''import SwiftUI

struct SMSDraftInboxView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var drafts: [SMSImportDraft] = []
    @State private var notice: String?

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            if drafts.isEmpty {
                ContentUnavailableView(
                    "No SMS Drafts",
                    systemImage: "tray",
                    description: Text("Only new, never-reviewed bank SMS will appear here.")
                )
            } else {
                ForEach(drafts) { draft in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(draft.vendor)
                                    .font(.headline)
                                Text("**\\(draft.cardEnding) · \\(draft.sender)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\\(draft.currency) \\(draft.amount.formatted())")
                                .font(.headline)
                        }

                        HStack {
                            Label(draft.suggestedNature, systemImage: natureIcon(draft.kind))
                            Spacer()
                            Text(draft.date.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)

                        Text(draft.details)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .textSelection(.enabled)

                        HStack(spacing: 12) {
                            Button(role: .destructive) {
                                reject(draft)
                            } label: {
                                Label("Reject", systemImage: "xmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                approve(draft)
                            } label: {
                                Label("Approve", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("SMS Drafts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onReceive(timer) { _ in reload() }
        .alert("SMS Draft", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button("OK", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    private func approve(_ draft: SMSImportDraft) {
        let configuration = SMSImportConsoleService.loadConfiguration()
        guard store.approveSMSDraft(draft, configuration: configuration) else {
            notice = store.errorMessage ?? "This draft could not be approved."
            return
        }
        do {
            try SMSImportConsoleService.completeDraft(draft)
            reload()
        } catch {
            notice = "The transaction was recorded, but the draft status could not be saved. Approving it again is safe because the transaction ID is duplicate-protected."
        }
    }

    private func reject(_ draft: SMSImportDraft) {
        do {
            try SMSImportConsoleService.completeDraft(draft)
            reload()
        } catch {
            notice = "The draft could not be rejected: \\(error.localizedDescription)"
        }
    }

    private func reload() {
        drafts = SMSImportConsoleService.loadDrafts().sorted {
            if $0.rowID != $1.rowID { return $0.rowID > $1.rowID }
            return $0.queuedAt > $1.queuedAt
        }
    }

    private func natureIcon(_ kind: String) -> String {
        switch kind {
        case "cashback", "income": return "arrow.down.circle.fill"
        case "withdrawal", "billPayment": return "arrow.left.arrow.right.circle.fill"
        default: return "arrow.up.circle.fill"
        }
    }
}
'''
write("DailyLedger/Views/SMSDraftInboxView.swift", inbox)

print("Added sender/card safety filters, newest-first unrecorded sync, and one-by-one SMS draft approval.")
