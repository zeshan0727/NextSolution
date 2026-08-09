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
        raise RuntimeError(f"Expected exactly one match in {path}, found {count}: {old[:220]!r}")
    write(path, text.replace(old, new, 1))


# ---------------------------------------------------------------------------
# Release versions. App 1.3.61 / build 69. SMS daemon 2.2.2.
# ---------------------------------------------------------------------------
replace_once("project.yml", 'MARKETING_VERSION: "1.3.60"', 'MARKETING_VERSION: "1.3.61"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "68"', 'CURRENT_PROJECT_VERSION: "69"')

source = "RootHideSMSQueue/Sources/main.m"
replace_once(source, 'static NSString *const kDaemonVersion = @"2.2.1";', 'static NSString *const kDaemonVersion = @"2.2.2";')
replace_once("RootHideSMSQueue/control", "Version: 2.2.1", "Version: 2.2.2")
for path in ["RootHideSMSQueue/postinst", "RootHideSMSQueue/layout/DEBIAN/postinst"]:
    text = read(path)
    text = text.replace("Next Ledger SMS Daemon 2.2.1 installation started",
                        "Next Ledger SMS Daemon 2.2.2 installation started")
    write(path, text)


# ---------------------------------------------------------------------------
# Remove unsafe keyed-unarchive attempts from Messages attributedBody.
# iOS Messages commonly stores typedstream data. The old unarchive call could
# stall a manual latest-15 scan before the review JSON was written.
# ---------------------------------------------------------------------------
text = read(source)
message_text_pattern = re.compile(
    r'''static NSString \*MessageText\(sqlite3_stmt \*statement\) \{.*?\n\}\n\n(?=static NSString \*ReviewTextFromAttributedBody)''',
    re.S,
)
message_text_replacement = r'''static NSString *MessageText(sqlite3_stmt *statement) {
    const unsigned char *textBytes = sqlite3_column_text(statement, 2);
    if (textBytes) {
        NSString *text = [NSString stringWithUTF8String:(const char *)textBytes];
        NSString *clean = CleanBankMessage(text);
        if (clean.length > 0) return clean;
    }

    const void *bytes = sqlite3_column_blob(statement, 3);
    int length = sqlite3_column_bytes(statement, 3);
    if (!bytes || length <= 0) return nil;

    // Typedstream-safe bounded scan. Never invoke NSKeyedUnarchiver here.
    int safeLength = MIN(length, 524288);
    return TextFromAttributedBody(bytes, safeLength);
}

'''
text, count = message_text_pattern.subn(message_text_replacement, text, count=1)
if count != 1:
    raise RuntimeError(f"Could not replace MessageText safely: {count}")

review_message_pattern = re.compile(
    r'''static NSString \*ReviewMessageText\(sqlite3_stmt \*statement\) \{.*?\n\}\n\n(?=static NSInteger CollectLatestIncomingMessagesForReview)''',
    re.S,
)
review_message_replacement = r'''static NSString *ReviewMessageText(sqlite3_stmt *statement) {
    const unsigned char *textBytes = sqlite3_column_text(statement, 2);
    if (textBytes) {
        NSString *value = [NSString stringWithUTF8String:(const char *)textBytes];
        if (value.length > 0) return value; // preserve complete m.text verbatim
    }

    const void *bytes = sqlite3_column_blob(statement, 3);
    int length = sqlite3_column_bytes(statement, 3);
    if (!bytes || length <= 0) return nil;

    // Manual review must never hang on typedstream data. Scan a bounded amount
    // and prefer the transaction-aware extractor, then the generic full-text one.
    int safeLength = MIN(length, 524288);
    NSString *transactionText = TextFromAttributedBody(bytes, safeLength);
    if (transactionText.length > 0) return transactionText;
    return ReviewTextFromAttributedBody(bytes, safeLength);
}

'''
text, count = review_message_pattern.subn(review_message_replacement, text, count=1)
if count != 1:
    raise RuntimeError(f"Could not replace ReviewMessageText safely: {count}")
write(source, text)


# ---------------------------------------------------------------------------
# Latest-15 collection: every database row must reach review even if text cannot
# be decoded. Also publish progress before decoding and notify the app on finish.
# ---------------------------------------------------------------------------
text = read(source)
old = '''        rowNumber += 1;
        sqlite3_int64 rowID = sqlite3_column_int64(statement, 0);
        NSString *details = ReviewMessageText(statement);
        if (details.length == 0) {
            AddLog(@"warning", @"Latest-15 row %lld had no recoverable message text.", rowID);
            continue;
        }
'''
new = '''        rowNumber += 1;
        sqlite3_int64 rowID = sqlite3_column_int64(statement, 0);

        gState[@"scanProgressCurrent"] = @(MIN(rowNumber, limit));
        gState[@"scanProgressTotal"] = @(limit);
        gState[@"scanPhase"] = [NSString stringWithFormat:@"Reading message %ld of %ld",
                                 (long)MIN(rowNumber, limit), (long)limit];
        WriteConsole(@"Reading latest incoming Messages database rows…");

        NSString *details = ReviewMessageText(statement);
        if (details.length == 0) {
            details = [NSString stringWithFormat:@"[Message row %lld: body could not be decoded safely. Keep for user review.]", rowID];
            AddLog(@"warning", @"Latest-15 row %lld was kept for review with an unreadable-body marker.", rowID);
        }
'''
if text.count(old) != 1:
    raise RuntimeError(f"Latest-15 row block match count: {text.count(old)}")
text = text.replace(old, new, 1)

# Remove the duplicate progress update later in the loop.
progress_block = '''
        gState[@"scanProgressCurrent"] = @(MIN(rowNumber, limit));
        gState[@"scanProgressTotal"] = @(limit);
        gState[@"scanPhase"] = [NSString stringWithFormat:@"Collecting message %ld of %ld for review",
                                 (long)MIN(rowNumber, limit), (long)limit];
        WriteConsole(@"Collecting latest incoming messages for review…");
'''
if progress_block in text:
    text = text.replace(progress_block, "", 1)

finish_old = '''    gState[@"manualReviewCount"] = @(items.count);
    AddLog(@"success", @"Collected %ld latest incoming message%@ with complete text for user review.",
           (long)items.count, items.count == 1 ? @"" : @"s");
    return items.count;
'''
finish_new = '''    gState[@"manualReviewCount"] = @(items.count);
    AddLog(@"success", @"Collected %ld latest incoming message%@ for user review.",
           (long)items.count, items.count == 1 ? @"" : @"s");
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)kDarwinChangeNotification,
        NULL, NULL, true
    );
    return items.count;
'''
if text.count(finish_old) != 1:
    raise RuntimeError("Latest-15 finish block not found")
text = text.replace(finish_old, finish_new, 1)
write(source, text)


# ---------------------------------------------------------------------------
# Bank message preservation and local parser coverage for the user's real CB SMS:
# ATM cash deposit, normal card purchase, and reversal/refund.
# ---------------------------------------------------------------------------
text = read(source)
pattern_anchor = '''        @"\\\\b(Current Acc\\\\s+x{2,}\\\\d{4,8}\\\\s+credited with\\\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\\\s*[0-9][0-9,]*(?:\\\\.[0-9]{1,2})?\\\\s+for Fawran instant payment.*?Current Acc Bal:\\\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\\\s*[0-9][0-9,]*(?:\\\\.[0-9]{1,2})?)\\\\b"
'''
if pattern_anchor not in text:
    raise RuntimeError("CleanBankMessage Fawran pattern anchor not found")
extra_patterns = '''        @"\\\\b(Current Acc\\\\s+x{2,}\\\\d{4,8}\\\\s+credited with\\\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\\\s*[0-9][0-9,]*(?:\\\\.[0-9]{1,2})?\\\\s+for ATM Cash Deposit.*?Current Acc Bal:\\\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\\\s*[0-9][0-9,]*(?:\\\\.[0-9]{1,2})?)\\\\b",
        @"\\\\b(Reversal of transaction on your card ending\\\\s+\\\\*\\\\*\\\\d{4}.*?for\\\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\\\s*[0-9][0-9,]*(?:\\\\.[0-9]{1,2})?.*?Available Limit(?:\\\\s+is|:)?\\\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)?\\\\s*[0-9][0-9,]*(?:\\\\.[0-9]{1,2})?)\\\\b",
'''
text = text.replace(pattern_anchor, extra_patterns + pattern_anchor, 1)

kind_old = '''    if ([lower containsString:@"cashback"] && [lower containsString:@"credited"]) kind = @"cashback";
    else if ([lower containsString:@"withdrawal using"]) kind = @"withdrawal";
    else if ([lower containsString:@"current acc"] && [lower containsString:@"credited with"] && [lower containsString:@"fawran instant payment"]) kind = @"incomingTransfer";
    else if ([lower containsString:@"used for"] || [lower containsString:@"purchase"] || [lower containsString:@"debited"]) kind = @"expense";
    else if ([lower containsString:@"credited to"] || [lower containsString:@"received"]) kind = @"income";
'''
kind_new = '''    if ([lower containsString:@"reversal of transaction"] && [lower containsString:@"card ending"]) kind = @"reversal";
    else if ([lower containsString:@"cashback"] && [lower containsString:@"credited"]) kind = @"cashback";
    else if ([lower containsString:@"withdrawal using"]) kind = @"withdrawal";
    else if ([lower containsString:@"current acc"] && [lower containsString:@"credited with"] && [lower containsString:@"atm cash deposit"]) kind = @"cashDeposit";
    else if ([lower containsString:@"current acc"] && [lower containsString:@"credited with"] && [lower containsString:@"fawran instant payment"]) kind = @"incomingTransfer";
    else if ([lower containsString:@"used for"] || [lower containsString:@"purchase"] || [lower containsString:@"debited"]) kind = @"expense";
    else if ([lower containsString:@"credited to"] || [lower containsString:@"received"]) kind = @"income";
'''
if text.count(kind_old) != 1:
    raise RuntimeError("ParseTransaction kind block not found")
text = text.replace(kind_old, kind_new, 1)

vendor_old = '''    } else if ([kind isEqualToString:@"cashback"]) {
        vendor = @"Credit Card Cashback";
    } else {
'''
vendor_new = '''    } else if ([kind isEqualToString:@"cashback"]) {
        vendor = @"Credit Card Cashback";
    } else if ([kind isEqualToString:@"reversal"]) {
        vendor = Capture(@"\\\\bat\\\\s+(.+?)(?=\\\\s+for\\\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)|$)", clean, 1) ?: @"Transaction Reversal";
    } else if ([kind isEqualToString:@"cashDeposit"]) {
        vendor = @"ATM Cash Deposit";
    } else {
'''
if text.count(vendor_old) != 1:
    raise RuntimeError("ParseTransaction vendor block not found")
text = text.replace(vendor_old, vendor_new, 1)

# Never auto-record review-sensitive transaction types.
auto_old = '''    if ([parsed[@"kind"] isEqualToString:@"incomingTransfer"]) {
        AddLog(@"info", @"Fawran transfer kept as draft for From/To account review.");
        return ImportResultWaitingForMapping;
    }
'''
auto_new = '''    if ([parsed[@"kind"] isEqualToString:@"incomingTransfer"] ||
        [parsed[@"kind"] isEqualToString:@"cashDeposit"] ||
        [parsed[@"kind"] isEqualToString:@"reversal"]) {
        AddLog(@"info", @"%@ kept as draft for user review.", parsed[@"kind"]);
        return ImportResultWaitingForMapping;
    }
'''
if text.count(auto_old) != 1:
    raise RuntimeError("AutoRecord review-sensitive block not found")
text = text.replace(auto_old, auto_new, 1)

# Self-test the exact examples from the user's screenshots.
test_anchor = '''        @{
            @"name": @"incoming Fawran transfer",
'''
if test_anchor not in text:
    raise RuntimeError("Self-test insertion anchor not found")
new_tests = '''        @{
            @"name": @"ATM cash deposit",
            @"sms": @"Current Acc xxx364001 credited with QAR 14,000.00 for ATM Cash Deposit at 13:27, 09-Aug-26 Current Acc Bal: QAR 15,332.55",
            @"kind": @"cashDeposit", @"ending": @"364001", @"amount": @"14000"
        },
        @{
            @"name": @"CB card purchase exact format",
            @"sms": @"Your card ending **6760 used for QAR 8.73 at MFT*badrgo W.L.L Doh at 15:31 09-Aug-26 Available Limit: QAR 105.60",
            @"kind": @"expense", @"ending": @"6760", @"amount": @"8.73"
        },
        @{
            @"name": @"CB reversal refund",
            @"sms": @"Reversal of transaction on your card ending **6760 at MFT*badrgo W.L.L Doh for QAR 8.73 at 15:35, 09-Aug-26 Available Limit: 114.33",
            @"kind": @"reversal", @"ending": @"6760", @"amount": @"8.73"
        },
'''
text = text.replace(test_anchor, new_tests + test_anchor, 1)
write(source, text)


# ---------------------------------------------------------------------------
# Draft semantics: reversal is a refund/income; ATM cash deposit is a transfer.
# ---------------------------------------------------------------------------
service = "DailyLedger/Services/SMSImportConsoleService.swift"
text = read(service)
text = text.replace(
    'case "cashback", "income", "reviewIncome": return .income',
    'case "cashback", "reversal", "income", "reviewIncome": return .income',
    1,
)
text = text.replace(
    'case "withdrawal", "incomingTransfer", "reviewTransfer": return .transfer',
    'case "withdrawal", "incomingTransfer", "cashDeposit", "reviewTransfer": return .transfer',
    1,
)

# Preserve AI's refund category by converting income+Refund/Reversal to kind reversal.
old = '''        let kind: String
        switch result.transactionType {
        case "income": kind = "reviewIncome"
        case "transfer": kind = "reviewTransfer"
        default: kind = "reviewExpense"
        }
'''
new = '''        let kind: String
        let normalizedCategory = result.category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch result.transactionType {
        case "income":
            kind = (normalizedCategory.contains("refund") || normalizedCategory.contains("reversal"))
                ? "reversal"
                : "reviewIncome"
        case "transfer": kind = "reviewTransfer"
        default: kind = "reviewExpense"
        }
'''
if text.count(old) != 1:
    raise RuntimeError("AI recovery kind block not found")
text = text.replace(old, new, 1)
write(service, text)

# Refund category in ledger draft categorizer.
ledger = "DailyLedger/Services/LedgerStore.swift"
text = read(ledger)
text = text.replace(
    'if draft.kind == "cashback" { return "Refund" }',
    'if draft.kind == "cashback" || draft.kind == "reversal" { return "Refund" }',
    1,
)
write(ledger, text)


# ---------------------------------------------------------------------------
# Latest-15 AI: use previous ledger/vendor data as hints, not as authority.
# The complete SMS remains the primary evidence; AI never auto-records.
# ---------------------------------------------------------------------------
view = "DailyLedger/Views/SMSLatest15ReviewView.swift"
text = read(view)
text = text.replace(
    '    static func analyze(_ item: SMSLatestReviewMessage) async throws -> SMSLatestReviewAIResult {',
    '    static func analyze(_ item: SMSLatestReviewMessage, historyContext: String) async throws -> SMSLatestReviewAIResult {',
    1,
)
text = text.replace(
    '''        You help a user review one complete incoming phone message for a personal ledger. Return JSON only. Classify it as income, expense, transfer, not_transaction, or unknown. Never invent an amount, currency, account, merchant, or direction. OTPs, marketing, login/security notices, balance-only notices, declined/failed notices without a posted movement, and personal chat messages are not_transaction. If it may be financial but you cannot determine the movement, use unknown. Confidence is 0 to 1.
''',
    '''        You help a user review one complete incoming phone message for a personal ledger. Return JSON only. Classify it as income, expense, transfer, not_transaction, or unknown. Never invent an amount, currency, account, merchant, or direction. OTPs, marketing, login/security notices, balance-only notices, declined/failed notices without a posted movement, and personal chat messages are not_transaction. If it may be financial but you cannot determine the movement, use unknown. Confidence is 0 to 1. Use previous-ledger examples only as hints. A card transaction reversal/refund should be income with category Refund. An ATM cash deposit credited to a bank account is normally a transfer from Cash to Bank, not ordinary income, unless the message/history clearly indicates otherwise.
''',
    1,
)
text = text.replace(
    '''        Complete message text:
        \\(item.details)
        """
''',
    '''        Complete message text:
        \\(item.details)

        Previous ledger/category hints (may be empty; never override the actual SMS):
        \\(historyContext)
        """
''',
    1,
)

# Environment store is used only to provide compact prior-category hints.
text = text.replace(
    'struct SMSLatest15ReviewView: View {\n',
    'struct SMSLatest15ReviewView: View {\n    @EnvironmentObject private var store: LedgerStore\n',
    1,
)

# Both AI call sites use the same local history context.
text = text.replace(
    'let result = try await SMSLatest15AIService.analyze(item)',
    'let result = try await SMSLatest15AIService.analyze(item, historyContext: historyContext(for: item))',
)

# Add helper before canCreateDraft.
helper_anchor = '    private func canCreateDraft(_ result: SMSLatestReviewAIResult) -> Bool {\n'
if helper_anchor not in text:
    raise RuntimeError("history helper anchor not found")
helper = r'''    private func historyContext(for item: SMSLatestReviewMessage) -> String {
        let normalizedMessage = item.details.lowercased()
        let messageTokens = Set(
            normalizedMessage
                .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count >= 4 }
        )

        var examples: [(score: Int, text: String)] = []
        for transaction in store.transactions.prefix(150) {
            let vendor = (transaction.vendor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let accountName = store.account(withID: transaction.accountID)?.name ?? ""
            let candidateText = "\(vendor) \(transaction.details) \(accountName)".lowercased()
                .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            let candidateTokens = Set(candidateText.split(separator: " ").map(String.init).filter { $0.count >= 4 })
            let overlap = messageTokens.intersection(candidateTokens).count
            var score = overlap
            if !vendor.isEmpty && normalizedMessage.localizedCaseInsensitiveContains(vendor) { score += 6 }
            let digits = accountName.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            if digits.count >= 4, normalizedMessage.contains(String(digits.suffix(4))) { score += 4 }
            guard score > 0 else { continue }

            let nature: String
            if transaction.refundOfTransactionID != nil { nature = "Refund" }
            else { nature = transaction.type.title }
            examples.append((score, "\(nature) | category=\(transaction.category) | vendor=\(vendor.isEmpty ? "Unknown" : vendor) | account=\(accountName.isEmpty ? "Unknown" : accountName)"))
        }

        examples.sort { left, right in
            left.score == right.score ? left.text < right.text : left.score > right.score
        }
        var lines = Array(examples.prefix(8).map(\.text))

        for rule in store.settings.vendorRules.prefix(80) {
            if normalizedMessage.localizedCaseInsensitiveContains(rule.keyword) {
                lines.append("Learned vendor rule | \(rule.keyword) => \(rule.category)")
            }
            if lines.count >= 10 { break }
        }

        if normalizedMessage.contains("reversal of transaction") {
            lines.insert("Local format hint | card reversal => Refund (money returned)", at: 0)
        }
        if normalizedMessage.contains("atm cash deposit") && normalizedMessage.contains("credited") {
            lines.insert("Local format hint | ATM cash deposit credited => usually Cash to Bank transfer", at: 0)
        }
        if normalizedMessage.contains("used for") && normalizedMessage.contains("card ending") {
            lines.insert("Local format hint | card used for merchant amount => Expense", at: 0)
        }

        return lines.isEmpty ? "No similar previous data found." : lines.prefix(10).joined(separator: "\n")
    }

'''
text = text.replace(helper_anchor, helper + helper_anchor, 1)
write(view, text)

print("Prepared Next Ledger 1.3.61 / daemon 2.2.2: typedstream-safe latest-15 capture, ATM deposit/card purchase/reversal parsing, and history-aware AI review.")
