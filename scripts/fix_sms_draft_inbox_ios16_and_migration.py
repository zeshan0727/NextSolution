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
        raise RuntimeError(f"Expected one match in {path}, found {count}: {old[:200]!r}")
    write(path, text.replace(old, new, 1))


service = "DailyLedger/Services/SMSImportConsoleService.swift"
replace_once(
    service,
    '''struct SMSImportConfiguration: Codable, Equatable {
    var enabled = true
    var cardAccountIDs: [String: String] = [:]
    var cashAccountID: String?
    var loanPaymentAccountID: String?
    var approvedSenders: [String] = ["Cb SMS"]
    var scanRequestID = 0
}
''',
    '''struct SMSImportConfiguration: Codable, Equatable {
    var enabled = true
    var cardAccountIDs: [String: String] = [:]
    var cashAccountID: String?
    var loanPaymentAccountID: String?
    var approvedSenders: [String] = ["Cb SMS"]
    var scanRequestID = 0

    enum CodingKeys: String, CodingKey {
        case enabled
        case cardAccountIDs
        case cashAccountID
        case loanPaymentAccountID
        case approvedSenders
        case scanRequestID
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        cardAccountIDs = try container.decodeIfPresent([String: String].self, forKey: .cardAccountIDs) ?? [:]
        cashAccountID = try container.decodeIfPresent(String.self, forKey: .cashAccountID)
        loanPaymentAccountID = try container.decodeIfPresent(String.self, forKey: .loanPaymentAccountID)
        approvedSenders = try container.decodeIfPresent([String].self, forKey: .approvedSenders) ?? ["Cb SMS"]
        scanRequestID = try container.decodeIfPresent(Int.self, forKey: .scanRequestID) ?? 0
    }
}
''',
)

replace_once(
    service,
    '''            if reviewed.count > 10_000 {
                reviewed.removeFirst(reviewed.count - 10_000)
            }
            try JSONEncoder().encode(reviewed).write(to: reviewedURL, options: .atomic)
''',
    '''            try JSONEncoder().encode(reviewed).write(to: reviewedURL, options: .atomic)
''',
)

replace_once(
    service,
    '''    private static func withDraftLock<T>(_ work: () throws -> T) throws -> T {
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
''',
    '''    private static func withDraftLock<T>(_ work: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return try work() }
        var writeLock = flock()
        writeLock.l_type = Int16(F_WRLCK)
        writeLock.l_whence = Int16(SEEK_SET)
        guard fcntl(descriptor, F_SETLKW, &writeLock) != -1 else {
            Darwin.close(descriptor)
            return try work()
        }
        defer {
            var unlock = flock()
            unlock.l_type = Int16(F_UNLCK)
            unlock.l_whence = Int16(SEEK_SET)
            _ = fcntl(descriptor, F_SETLK, &unlock)
            Darwin.close(descriptor)
        }
        return try work()
    }
''',
)

inbox = "DailyLedger/Views/SMSDraftInboxView.swift"
replace_once(
    inbox,
    '''                ContentUnavailableView(
                    "No SMS Drafts",
                    systemImage: "tray",
                    description: Text("Only new, never-reviewed bank SMS will appear here.")
                )
''',
    '''                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("No SMS Drafts")
                        .font(.headline)
                    Text("Only new, never-reviewed bank SMS will appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
''',
)

source = "RootHideSMSQueue/Sources/main.m"
replace_once(
    source,
    '''    NSInteger ignoredCard = 0;
    NSInteger parseFailures = 0;
''',
    '''    NSInteger ignoredCard = 0;
    NSInteger parseFailures = 0;
    BOOL draftWriteFailed = NO;
''',
)
replace_once(
    source,
    '''        else AddLog(@"error", @"Could not save approval draft for SMS row %lld.", rowID);
''',
    '''        else {
            draftWriteFailed = YES;
            AddLog(@"error", @"Could not save approval draft for SMS row %lld; the database cursor will not advance.", rowID);
        }
''',
)
replace_once(
    source,
    '''    gState[@"lastRowID"] = @(maximum);
    gState[@"lastScanRequestID"] = @(requestID);
''',
    '''    if (!draftWriteFailed) {
        gState[@"lastRowID"] = @(maximum);
    } else {
        AddLog(@"warning", @"Retaining the previous SMS row cursor so unrecorded messages are retried.");
    }
    gState[@"lastScanRequestID"] = @(requestID);
''',
)

print("Fixed iOS 16 draft inbox UI, migrated old settings, coordinated file locks, and retained failed SMS rows for retry.")
