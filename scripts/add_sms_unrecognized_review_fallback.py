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


source = "RootHideSMSQueue/Sources/main.m"
replace_once(
    source,
    'static NSString *const kDaemonVersion = @"2.1.6";',
    'static NSString *const kDaemonVersion = @"2.1.7";',
)

fallback_helpers = r'''
static BOOL LooksLikeTransactionForReview(NSString *text) {
    NSString *clean = CleanWhitespace(text);
    NSString *lower = clean.lowercaseString;
    NSString *currency = Capture(@"\\b(QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\b", clean, 1);
    if (currency.length == 0) return NO;

    NSArray<NSString *> *signals = @[
        @"credited", @"debited", @"used for", @"purchase", @"withdrawal",
        @"transfer", @"fawran", @"instant payment", @"received", @"sent",
        @"payment", @"remittance"
    ];
    for (NSString *signal in signals) {
        if ([lower containsString:signal]) return YES;
    }
    return NO;
}

static NSDictionary *ReviewDraftForUnrecognizedBankSMS(NSString *text, NSDate *fallbackDate) {
    NSString *clean = CleanWhitespace(text);
    if (!LooksLikeTransactionForReview(clean)) return nil;

    NSString *currency = Capture(@"\\b(QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\b", clean, 1);
    NSString *amountText = Capture(@"\\b(QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\b", clean, 2);
    if (!currency || !amountText) return nil;
    if ([currency.uppercaseString isEqualToString:@"QR"]) currency = @"QAR";
    amountText = [amountText stringByReplacingOccurrencesOfString:@"," withString:@""];
    NSDecimalNumber *amount = [NSDecimalNumber decimalNumberWithString:amountText locale:@{NSLocaleDecimalSeparator: @"."}];
    if ([amount isEqualToNumber:NSDecimalNumber.notANumber] || amount.doubleValue <= 0) return nil;

    NSString *lower = clean.lowercaseString;
    NSString *kind = @"reviewTransaction";
    if ([lower containsString:@"transfer"] ||
        [lower containsString:@"fawran"] ||
        [lower containsString:@"instant payment"] ||
        [lower containsString:@"remittance"] ||
        [lower containsString:@"sent to"]) {
        kind = @"reviewTransfer";
    } else if ([lower containsString:@"credited"] || [lower containsString:@"received"]) {
        kind = @"reviewIncome";
    } else if ([lower containsString:@"debited"] ||
               [lower containsString:@"used for"] ||
               [lower containsString:@"purchase"] ||
               [lower containsString:@"withdrawal"]) {
        kind = @"reviewExpense";
    }

    NSString *ending = Capture(@"\\*\\*(\\d{4,8})", clean, 1);
    if (!ending) ending = Capture(@"\\b(?:Current\\s+)?Acc(?:ount)?\\s+x{2,}(\\d{4,8})\\b", clean, 1);
    if (!ending) ending = @"";

    NSString *vendor = Capture(@"\\bref\\s+(.+?)(?=\\s+withM-|\\s+at\\s+\\d{1,2}:\\d{2}|$)", clean, 1);
    if (!vendor) vendor = Capture(@"\\bat\\s+(.+?)(?=\\s+at\\s+\\d{1,2}:\\d{2}|\\s+on\\s+\\d|\\s+balance|\\s+available|$)", clean, 1);
    if (!vendor) vendor = Capture(@"\\bfrom\\s+(.+?)(?=\\s+at\\s+\\d|\\s+on\\s+\\d|$)", clean, 1);
    vendor = CleanWhitespace(vendor ?: @"Review Required");

    return @{
        @"kind": kind,
        @"currency": currency.uppercaseString,
        @"amount": amount,
        @"cardEnding": ending,
        @"vendor": vendor,
        @"date": ISODate(TransactionDate(clean, fallbackDate)),
        @"details": clean
    };
}

'''
replace_once(
    source,
    'static NSString *SMSDatabasePath(void) {\n',
    fallback_helpers + 'static NSString *SMSDatabasePath(void) {\n',
)

replace_once(
    source,
    '''    NSInteger parseFailures = 0;\n    NSInteger blankBodies = 0;\n''',
    '''    NSInteger parseFailures = 0;\n    NSInteger reviewFallbacks = 0;\n    NSInteger blankBodies = 0;\n''',
)

old_parse_block = '''        NSDictionary *parsed = ParseTransaction(text, DatabaseDate(sqlite3_column_int64(statement, 4)));\n        if (!parsed) {\n            parseFailures += 1;\n            NSString *preview = text.length > 160 ? [[text substringToIndex:160] stringByAppendingString:@"…"] : text;\n            AddLog(@"warning", @"Approved-bank SMS row %lld was not classified: %@", rowID, preview);\n            continue;\n        }\n        BOOL requiresMappedEnding = ![parsed[@"kind"] isEqualToString:@"incomingTransfer"];\n'''
new_parse_block = '''        NSDictionary *parsed = ParseTransaction(text, DatabaseDate(sqlite3_column_int64(statement, 4)));\n        BOOL reviewFallback = NO;\n        if (!parsed) {\n            parsed = ReviewDraftForUnrecognizedBankSMS(\n                text, DatabaseDate(sqlite3_column_int64(statement, 4))\n            );\n            if (!parsed) {\n                parseFailures += 1;\n                NSString *preview = text.length > 160 ? [[text substringToIndex:160] stringByAppendingString:@"…"] : text;\n                AddLog(@"warning", @"Approved-bank SMS row %lld was not classified and did not look transactional: %@", rowID, preview);\n                continue;\n            }\n            reviewFallback = YES;\n            reviewFallbacks += 1;\n            AddLog(@"info", @"SMS row %lld could not be classified confidently; created a manual-review candidate (%@).", rowID, parsed[@"kind"]);\n        }\n        BOOL requiresMappedEnding = !reviewFallback && ![parsed[@"kind"] isEqualToString:@"incomingTransfer"];\n'''
replace_once(source, old_parse_block, new_parse_block)

replace_once(
    source,
    '''            ImportResult automaticResult = AutoRecordParsedEvent(parsed, sourceKey, sender, config);\n''',
    '''            ImportResult automaticResult = reviewFallback\n                ? ImportResultWaitingForMapping\n                : AutoRecordParsedEvent(parsed, sourceKey, sender, config);\n''',
)

replace_once(
    source,
    '''ignored card %ld; unreadable %ld; parse failures %ld; draft failures %ld.''',
    '''ignored card %ld; unreadable %ld; review fallback %ld; parse failures %ld; draft failures %ld.''',
)
replace_once(
    source,
    '''        (long)blankBodies,\n        (long)parseFailures,\n''',
    '''        (long)blankBodies,\n        (long)reviewFallbacks,\n        (long)parseFailures,\n''',
)

# App-side suggestions: the fallback is always editable and never auto-recorded.
service = "DailyLedger/Services/SMSImportConsoleService.swift"
service_text = read(service)
service_text = service_text.replace(
    'case "cashback", "income": return .income',
    'case "cashback", "income", "reviewIncome": return .income',
    1,
)
service_text = service_text.replace(
    'case "withdrawal", "incomingTransfer": return .transfer',
    'case "withdrawal", "incomingTransfer", "reviewTransfer": return .transfer',
    1,
)
write(service, service_text)

# Package version only; settings/configuration keys remain unchanged and therefore migrate exactly.
replace_once("RootHideSMSQueue/control", "Version: 2.1.6", "Version: 2.1.7")
for path in ["RootHideSMSQueue/postinst", "RootHideSMSQueue/layout/DEBIAN/postinst"]:
    replace_once(
        path,
        "Next Ledger SMS Daemon 2.1.6 installation started",
        "Next Ledger SMS Daemon 2.1.7 installation started",
    )

print("Added fail-safe approved-bank SMS review drafts and blocked uncertain messages from Auto Record.")
