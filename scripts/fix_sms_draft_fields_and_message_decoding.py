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
        raise RuntimeError(f"Expected one match in {path}, found {count}: {old[:220]!r}")
    write(path, text.replace(old, new, 1))


def replace_exact_count(path: str, old: str, new: str, expected: int) -> None:
    text = read(path)
    count = text.count(old)
    if count != expected:
        raise RuntimeError(f"Expected {expected} matches in {path}, found {count}: {old[:220]!r}")
    write(path, text.replace(old, new))


source = "RootHideSMSQueue/Sources/main.m"
replace_once(
    source,
    'static NSString *const kDaemonVersion = @"2.1.0";',
    'static NSString *const kDaemonVersion = @"2.1.1";',
)

replace_once(
    source,
    r'''static NSDate *TransactionDate(NSString *text, NSDate *fallback) {
    NSArray<NSDictionary *> *patterns = @[
        @{@"pattern": @"\\b(\\d{1,2}/\\d{1,2}/\\d{4})\\s+(\\d{1,2}:\\d{2})\\b", @"format": @"dd/MM/yyyy HH:mm"},
        @{@"pattern": @"\\b(\\d{1,2}/\\d{1,2}/\\d{2})\\s+(\\d{1,2}:\\d{2})\\b", @"format": @"dd/MM/yy HH:mm"},
        @{@"pattern": @"\\b(\\d{1,2}-[A-Za-z]{3}-\\d{4})\\s+(\\d{1,2}:\\d{2})\\b", @"format": @"dd-MMM-yyyy HH:mm"},
        @{@"pattern": @"\\b(\\d{1,2}-[A-Za-z]{3}-\\d{2})\\s+(\\d{1,2}:\\d{2})\\b", @"format": @"dd-MMM-yy HH:mm"}
    ];
    for (NSDictionary *item in patterns) {
        NSString *datePart = Capture(item[@"pattern"], text, 1);
        NSString *timePart = Capture(item[@"pattern"], text, 2);
        if (!datePart || !timePart) continue;
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = NSTimeZone.localTimeZone;
        formatter.dateFormat = item[@"format"];
        NSDate *date = [formatter dateFromString:[NSString stringWithFormat:@"%@ %@", datePart, timePart]];
        if (date) return date;
    }
    return fallback ?: NSDate.date;
}
''',
    r'''static NSDate *TransactionDate(NSString *text, NSDate *fallback) {
    NSArray<NSDictionary *> *patterns = @[
        @{@"pattern": @"\\b(\\d{1,2}/\\d{1,2}/\\d{4})\\s+(\\d{1,2}:\\d{2})\\b", @"format": @"dd/MM/yyyy HH:mm"},
        @{@"pattern": @"\\b(\\d{1,2}/\\d{1,2}/\\d{2})\\s+(\\d{1,2}:\\d{2})\\b", @"format": @"dd/MM/yy HH:mm"},
        @{@"pattern": @"\\b(\\d{1,2}-[A-Za-z]{3}-\\d{4})\\s+(\\d{1,2}:\\d{2})\\b", @"format": @"dd-MMM-yyyy HH:mm"},
        @{@"pattern": @"\\b(\\d{1,2}-[A-Za-z]{3}-\\d{2})\\s+(\\d{1,2}:\\d{2})\\b", @"format": @"dd-MMM-yy HH:mm"},
        @{@"pattern": @"\\b(\\d{1,2}:\\d{2})\\s+(\\d{1,2}-[A-Za-z]{3}-\\d{4})\\b", @"format": @"HH:mm dd-MMM-yyyy"},
        @{@"pattern": @"\\b(\\d{1,2}:\\d{2})\\s+(\\d{1,2}-[A-Za-z]{3}-\\d{2})\\b", @"format": @"HH:mm dd-MMM-yy"}
    ];
    for (NSDictionary *item in patterns) {
        NSString *first = Capture(item[@"pattern"], text, 1);
        NSString *second = Capture(item[@"pattern"], text, 2);
        if (!first || !second) continue;
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = NSTimeZone.localTimeZone;
        formatter.dateFormat = item[@"format"];
        NSDate *date = [formatter dateFromString:[NSString stringWithFormat:@"%@ %@", first, second]];
        if (date) return date;
    }
    return fallback ?: NSDate.date;
}
''',
)

replace_once(
    source,
    r'''        vendor = Capture(@"\\bused for\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,.]*\\s+at\\s+(.+?)(?=\\s+at\\s+\\d{1,2}/\\d{1,2}/\\d{2,4}|\\s+on\\s+\\d{1,2}/|\\s+available\\s+limit|$)", clean, 1);
''',
    r'''        vendor = Capture(@"\\b(?:was\\s+)?used for\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,.]*\\s+at\\s+(.+?)(?=\\s+at\\s+\\d{1,2}:\\d{2}\\s+\\d{1,2}-[A-Za-z]{3}-\\d{2,4}|\\s+at\\s+\\d{1,2}/\\d{1,2}/\\d{2,4}|\\s+on\\s+\\d{1,2}/|\\s+available\\s+limit|\\s+balance:|\\s+enquiry\\s+\\d+|$)", clean, 1);
''',
)

replace_once(
    source,
    r'''static NSString *TextFromAttributedBody(const void *bytes, int length) {
    if (!bytes || length <= 0) return nil;
    const unsigned char *raw = bytes;
    NSMutableArray<NSString *> *runs = [NSMutableArray array];
    int start = -1;
    for (int index = 0; index <= length; index++) {
        BOOL printable = index < length && raw[index] >= 32 && raw[index] <= 126;
        if (printable && start < 0) start = index;
        if (!printable && start >= 0) {
            int runLength = index - start;
            if (runLength >= 4) {
                NSString *run = [[NSString alloc] initWithBytes:raw + start length:(NSUInteger)runLength encoding:NSUTF8StringEncoding];
                if (run.length > 0) [runs addObject:run];
            }
            start = -1;
        }
    }
    return runs.count ? [runs componentsJoinedByString:@"\n"] : nil;
}

static NSString *MessageText(sqlite3_stmt *statement) {
    const unsigned char *textBytes = sqlite3_column_text(statement, 2);
    if (textBytes) {
        NSString *text = [NSString stringWithUTF8String:(const char *)textBytes];
        if (text.length > 0) return text;
    }
    const void *bytes = sqlite3_column_blob(statement, 3);
    int length = sqlite3_column_bytes(statement, 3);
    if (bytes && length > 0) {
        NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)length];
        @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            id decoded = [NSKeyedUnarchiver unarchiveObjectWithData:data];
#pragma clang diagnostic pop
            if ([decoded isKindOfClass:NSAttributedString.class]) return [decoded string];
            if ([decoded isKindOfClass:NSString.class]) return decoded;
        } @catch (__unused NSException *exception) {}
    }
    return TextFromAttributedBody(bytes, length);
}
''',
    r'''static NSString *StringFromDecodedObject(id object) {
    if ([object isKindOfClass:NSAttributedString.class]) return [object string];
    if ([object isKindOfClass:NSString.class]) return object;
    NSString *best = nil;
    NSArray *values = nil;
    if ([object isKindOfClass:NSDictionary.class]) values = [(NSDictionary *)object allValues];
    else if ([object isKindOfClass:NSArray.class]) values = object;
    for (id value in values ?: @[]) {
        NSString *candidate = StringFromDecodedObject(value);
        if (candidate.length > best.length) best = candidate;
    }
    return best;
}

static NSString *CleanBankMessage(NSString *candidate) {
    NSString *clean = CleanWhitespace(candidate ?: @"");
    if (clean.length == 0) return nil;

    NSArray<NSString *> *completePatterns = @[
        @"\\b(Your card ending\\s+\\*\\*\\d{4}\\s+(?:was\\s+)?used for\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?.*?Available Limit(?:\\s+is|:)?\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)?\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\b",
        @"\\b(Debit Card\\s+\\*\\*\\d{4}\\s+(?:was\\s+)?used for\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?.*?Enquiry\\s+\\d+)\\b",
        @"\\b(Debit Card\\s+\\*\\*\\d{4}\\s+(?:was\\s+)?used for\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?.*?Balance:\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\b",
        @"\\b(Withdrawal using Debit Card\\s+\\*\\*\\d{4}\\s+for\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?.*?available balance is\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\b",
        @"\\b(Bill Payment of\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?.*?was successful\\.?)",
        @"\\b(Cashback amount of\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?.*?Available Limit(?:\\s+is|:)?\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*[0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\b"
    ];
    for (NSString *pattern in completePatterns) {
        NSString *match = Capture(pattern, clean, 1);
        if (match.length > 0) return CleanWhitespace(match);
    }

    NSArray<NSString *> *archiveMarkers = @[
        @"streamtyped", @"NSAttributedString", @"NSMutableAttributedString",
        @"NSKeyedArchiver", @"NSDictionary", @"NS.rangeval", @"NS.objects",
        @"$classname", @"$classes"
    ];
    BOOL containsArchiveData = NO;
    for (NSString *marker in archiveMarkers) {
        if ([clean rangeOfString:marker options:NSCaseInsensitiveSearch].location != NSNotFound) {
            containsArchiveData = YES;
            break;
        }
    }
    if (containsArchiveData) return nil;
    return clean;
}

static NSString *TextFromAttributedBody(const void *bytes, int length) {
    if (!bytes || length <= 0) return nil;
    const unsigned char *raw = bytes;
    NSMutableArray<NSString *> *runs = [NSMutableArray array];
    int start = -1;
    for (int index = 0; index <= length; index++) {
        BOOL printable = index < length && raw[index] >= 32 && raw[index] <= 126;
        if (printable && start < 0) start = index;
        if (!printable && start >= 0) {
            int runLength = index - start;
            if (runLength >= 4) {
                NSString *run = [[NSString alloc] initWithBytes:raw + start length:(NSUInteger)runLength encoding:NSUTF8StringEncoding];
                if (run.length > 0) [runs addObject:run];
            }
            start = -1;
        }
    }
    return runs.count ? CleanBankMessage([runs componentsJoinedByString:@" "]) : nil;
}

static NSString *MessageText(sqlite3_stmt *statement) {
    const unsigned char *textBytes = sqlite3_column_text(statement, 2);
    if (textBytes) {
        NSString *text = [NSString stringWithUTF8String:(const char *)textBytes];
        NSString *clean = CleanBankMessage(text);
        if (clean.length > 0) return clean;
    }
    const void *bytes = sqlite3_column_blob(statement, 3);
    int length = sqlite3_column_bytes(statement, 3);
    if (bytes && length > 0) {
        NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)length];
        @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            id decoded = [NSKeyedUnarchiver unarchiveObjectWithData:data];
#pragma clang diagnostic pop
            NSString *clean = CleanBankMessage(StringFromDecodedObject(decoded));
            if (clean.length > 0) return clean;
        } @catch (__unused NSException *exception) {}
    }
    return TextFromAttributedBody(bytes, length);
}
''',
)

replace_once(
    source,
    "static NSString *QueueEvent(NSDictionary *parsed, NSString *sourceKey, NSString *sender) {",
    "__attribute__((unused)) static NSString *QueueEvent(NSDictionary *parsed, NSString *sourceKey, NSString *sender) {",
)
replace_once(
    source,
    "static void RetryPending(NSDictionary *config) {",
    "__attribute__((unused)) static void RetryPending(NSDictionary *config) {",
)

service = "DailyLedger/Services/SMSImportConsoleService.swift"
replace_once(
    service,
    '''    var suggestedNature: String {
        switch kind {
        case "cashback": return "Refund Income"
        case "income": return "Income"
        case "withdrawal": return "Transfer to Cash"
        case "billPayment": return "Loan Payment Transfer"
        default: return "Expense"
        }
    }
''',
    r'''    var transactionType: TransactionType {
        switch kind {
        case "cashback", "income": return .income
        case "withdrawal", "billPayment": return .transfer
        default: return .expense
        }
    }

    var displayType: String {
        switch transactionType {
        case .income: return "Income"
        case .expense: return "Expense"
        case .transfer: return "Transfer"
        }
    }

    var cleanedDescription: String {
        Self.extractMessage(from: details)
    }

    var cleanedVendor: String {
        let message = cleanedDescription
        let currencyPattern = "(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)"
        let amountPattern = "[0-9][0-9,]*(?:\\.[0-9]{1,2})?"
        let pattern: String
        switch kind {
        case "withdrawal":
            pattern = "(?i)\\bat\\s+(.+?)(?=\\s+your available|\\s+available balance|$)"
        case "billPayment":
            pattern = "(?i)\\bto\\s+(.+?)(?=\\s+on\\s+\\d|\\s+was successful|$)"
        case "cashback":
            return "Credit Card Cashback"
        case "income":
            pattern = "(?i)\\bfrom\\s+(.+?)(?=\\s+on\\s+\\d|\\s+at\\s+\\d|$)"
        default:
            pattern = "(?i)\\b(?:was\\s+)?used for\\s+\(currencyPattern)\\s*\(amountPattern)\\s+at\\s+(.+?)(?=\\s+at\\s+\\d{1,2}:\\d{2}\\s+\\d{1,2}-[A-Za-z]{3}-\\d{2,4}|\\s+at\\s+\\d{1,2}/\\d{1,2}/\\d{2,4}|\\s+available limit|\\s+balance:|\\s+enquiry\\s+\\d+|$)"
        }
        if let captured = Self.capture(pattern, in: message) {
            return captured.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return vendor
            .replacingOccurrences(
                of: "(?i)\\s+at\\s+\\d{1,2}:\\d{2}\\s+\\d{1,2}-[A-Za-z]{3}-\\d{2,4}.*$",
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractMessage(from raw: String) -> String {
        let compact = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let currency = "(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)"
        let amount = "[0-9][0-9,]*(?:\\.[0-9]{1,2})?"
        let patterns = [
            "(?i)\\b(Your card ending\\s+\\*\\*\\d{4}\\s+(?:was\\s+)?used for\\s+\(currency)\\s*\(amount).*?Available Limit(?:\\s+is|:)?\\s+\(currency)?\\s*\(amount))\\b",
            "(?i)\\b(Debit Card\\s+\\*\\*\\d{4}\\s+(?:was\\s+)?used for\\s+\(currency)\\s*\(amount).*?Enquiry\\s+\\d+)\\b",
            "(?i)\\b(Debit Card\\s+\\*\\*\\d{4}\\s+(?:was\\s+)?used for\\s+\(currency)\\s*\(amount).*?Balance:\\s+\(currency)\\s*\(amount))\\b",
            "(?i)\\b(Withdrawal using Debit Card\\s+\\*\\*\\d{4}\\s+for\\s+\(currency)\\s*\(amount).*?available balance is\\s+\(currency)\\s*\(amount))\\b",
            "(?i)\\b(Bill Payment of\\s+\(currency)\\s*\(amount).*?was successful\\.?)",
            "(?i)\\b(Cashback amount of\\s+\(currency)\\s*\(amount).*?Available Limit(?:\\s+is|:)?\\s+\(currency)\\s*\(amount))\\b"
        ]
        for pattern in patterns {
            if let value = capture(pattern, in: compact) { return value }
        }
        let archiveMarkers = [
            "streamtyped", "NSAttributedString", "NSMutableAttributedString",
            "NSKeyedArchiver", "NSDictionary", "NS.rangeval", "NS.objects",
            "$classname", "$classes"
        ]
        if archiveMarkers.contains(where: { compact.localizedCaseInsensitiveContains($0) }) {
            return ""
        }
        return compact
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
''',
)

store = "DailyLedger/Services/LedgerStore.swift"
replace_once(
    store,
    '''    @discardableResult
    func approveSMSDraft(_ draft: SMSImportDraft, configuration: SMSImportConfiguration) -> Bool {
''',
    r'''    func smsDraftCategory(for draft: SMSImportDraft) -> String {
        if draft.transactionType == .transfer { return "Transfer" }
        if draft.kind == "cashback" { return "Refund" }

        let vendorKey = normalizedSMSVendor(draft.cleanedVendor)
        if !vendorKey.isEmpty,
           let previous = transactions.first(where: {
               $0.type == draft.transactionType &&
               normalizedSMSVendor($0.vendor ?? "") == vendorKey &&
               !$0.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
           }) {
            return previous.category
        }

        guard let sourceText = SMSImportConsoleService.loadConfiguration().cardAccountIDs[draft.cardEnding],
              let sourceID = UUID(uuidString: sourceText) else {
            return "Other"
        }
        let probe = LedgerTransaction(
            id: draft.id,
            type: draft.transactionType,
            amount: draft.amount,
            date: draft.date,
            category: "Other",
            vendor: draft.cleanedVendor,
            details: draft.cleanedDescription,
            accountID: sourceID
        )
        return suggestedCategory(for: probe) ?? "Other"
    }

    private func normalizedSMSVendor(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    func approveSMSDraft(_ draft: SMSImportDraft, configuration: SMSImportConfiguration) -> Bool {
''',
)
replace_once(
    store,
    '''        let item: LedgerTransaction
        switch draft.kind {
''',
    '''        let cleanVendor = draft.cleanedVendor
        let cleanDetails = draft.cleanedDescription
        guard !cleanDetails.isEmpty else {
            errorMessage = "The original SMS text could not be decoded safely. Reject this draft and scan again after updating the daemon."
            return false
        }
        let resolvedCategory = smsDraftCategory(for: draft)

        let item: LedgerTransaction
        switch draft.kind {
''',
)
replace_exact_count(
    store,
    '''                vendor: draft.vendor,
                details: draft.details,
''',
    '''                vendor: cleanVendor,
                details: cleanDetails,
''',
    5,
)
replace_once(store, '                category: "Refund",\n', '                category: resolvedCategory,\n')
replace_once(store, '                category: "Other",\n                vendor: cleanVendor,\n                details: cleanDetails,\n                accountID: sourceID\n            )\n        default:', '                category: resolvedCategory,\n                vendor: cleanVendor,\n                details: cleanDetails,\n                accountID: sourceID\n            )\n        default:')
replace_once(
    store,
    '''                category: suggestedCategory(for: probe) ?? "Other",
''',
    '''                category: resolvedCategory,
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
                VStack(spacing: 10) {
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
            } else {
                ForEach(drafts) { draft in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(draft.cleanedVendor.isEmpty ? "Unknown Vendor" : draft.cleanedVendor)
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(draft.currency) \(draft.amount.formatted())")
                                .font(.headline)
                                .multilineTextAlignment(.trailing)
                        }

                        draftField(
                            title: "Date",
                            value: draft.date.formatted(date: .abbreviated, time: .shortened)
                        )
                        draftField(title: "Type", value: draft.displayType)
                        draftField(title: "Category", value: store.smsDraftCategory(for: draft))

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Description")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(draft.cleanedDescription.isEmpty ? "Unable to decode the SMS safely." : draft.cleanedDescription)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }

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
                            .disabled(draft.cleanedDescription.isEmpty)
                        }
                    }
                    .padding(.vertical, 8)
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

    private func draftField(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
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
            notice = "The draft could not be rejected: \(error.localizedDescription)"
        }
    }

    private func reload() {
        drafts = SMSImportConsoleService.loadDrafts().sorted {
            if $0.rowID != $1.rowID { return $0.rowID > $1.rowID }
            return $0.queuedAt > $1.queuedAt
        }
    }
}
'''
write("DailyLedger/Views/SMSDraftInboxView.swift", inbox)

# Fix the literal draft counter interpolation in the console as well.
console_view = "DailyLedger/Views/SMSImportConsoleView.swift"
replace_once(console_view, 'Text("\\\\(draftCount)")', 'Text("\\(draftCount)")')

for path in ["RootHideSMSQueue/control"]:
    replace_once(path, "Version: 2.1.0", "Version: 2.1.1")
for path in ["RootHideSMSQueue/postinst", "RootHideSMSQueue/layout/DEBIAN/postinst"]:
    replace_once(path, "Next Ledger SMS Daemon 2.1.0 installation started", "Next Ledger SMS Daemon 2.1.1 installation started")

print("Cleaned SMS extraction, simplified draft fields, and reused the latest same-vendor category.")
