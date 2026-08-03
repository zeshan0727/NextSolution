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
        raise RuntimeError(f"Expected one match in {path}, found {count}: {old[:240]!r}")
    write(path, text.replace(old, new, 1))


def replace_range(path: str, start: str, end: str, replacement: str) -> None:
    text = read(path)
    start_index = text.find(start)
    if start_index < 0:
        raise RuntimeError(f"Start marker missing in {path}: {start!r}")
    end_index = text.find(end, start_index)
    if end_index < 0:
        raise RuntimeError(f"End marker missing in {path}: {end!r}")
    write(path, text[:start_index] + replacement + text[end_index:])


# ---------------------------------------------------------------------------
# Financial Summary: classify transfers by native account nature and direction.
# Only Nature = Bank is a bank. Account groups alone never create income/expense.
# ---------------------------------------------------------------------------
store = "DailyLedger/Services/LedgerStore.swift"
replace_range(
    store,
    "    func isReportIncome(_ transaction: LedgerTransaction) -> Bool {\n",
    "    private func isAmaraTransfer(_ transaction: LedgerTransaction) -> Bool {\n",
    r'''    func isBankAccount(_ account: LedgerAccount?) -> Bool {
        account?.nature == .bank
    }

    func isFinancialLoanAccount(_ account: LedgerAccount?) -> Bool {
        guard let account else { return false }
        return account.nature == .loan || account.group == .payments
    }

    func isPaymentToBankTransfer(_ transaction: LedgerTransaction) -> Bool {
        guard transaction.type == .transfer,
              let source = account(withID: transaction.accountID),
              source.group == .payments else { return false }
        return isBankAccount(account(withID: transaction.destinationAccountID))
    }

    func isBankToPaymentTransfer(_ transaction: LedgerTransaction) -> Bool {
        guard transaction.type == .transfer,
              isBankAccount(account(withID: transaction.accountID)),
              let destination = account(withID: transaction.destinationAccountID) else {
            return false
        }
        return destination.group == .payments
    }

    func paymentSourceBalanceBefore(_ transaction: LedgerTransaction) -> Decimal? {
        guard isPaymentToBankTransfer(transaction),
              let sourceID = transaction.accountID else { return nil }
        guard let after = runningBalance(for: transaction.id, accountID: sourceID) else {
            return nil
        }
        return after + transaction.amount
    }

    func receivableCollectionAmount(_ transaction: LedgerTransaction) -> Decimal {
        guard let before = paymentSourceBalanceBefore(transaction), before > 0 else {
            return 0
        }
        return min(transaction.amount, before)
    }

    func paymentLoanIncreaseAmount(_ transaction: LedgerTransaction) -> Decimal {
        guard isPaymentToBankTransfer(transaction) else { return 0 }
        return max(0, transaction.amount - receivableCollectionAmount(transaction))
    }

    func paymentLoanPaymentAmount(_ transaction: LedgerTransaction) -> Decimal {
        loanDecreaseAmount(transaction)
    }

    func transferIncomeAmount(_ transaction: LedgerTransaction) -> Decimal {
        guard transaction.type == .transfer,
              let source = account(withID: transaction.accountID),
              let destination = account(withID: transaction.destinationAccountID),
              isBankAccount(destination),
              !isBankAccount(source) else { return 0 }

        if source.group == .payments {
            return receivableCollectionAmount(transaction)
        }
        guard source.nature != .loan else { return 0 }
        return transaction.destinationAmount ?? transaction.amount
    }

    func isReportIncome(_ transaction: LedgerTransaction) -> Bool {
        transaction.type == .income || transferIncomeAmount(transaction) > 0
    }

    func reportIncomeAmount(_ transaction: LedgerTransaction) -> Decimal {
        transaction.type == .income ? transaction.amount : transferIncomeAmount(transaction)
    }

    func reportIncomeAccountID(_ transaction: LedgerTransaction) -> UUID? {
        transaction.type == .transfer ? transaction.destinationAccountID : transaction.accountID
    }

    func reportIncomeConversionAccountID(_ transaction: LedgerTransaction) -> UUID? {
        if transaction.type == .transfer,
           account(withID: transaction.accountID)?.group == .payments {
            return transaction.accountID
        }
        return reportIncomeAccountID(transaction)
    }

    func isReportExpense(_ transaction: LedgerTransaction) -> Bool {
        if transaction.type == .expense { return true }
        guard transaction.type == .transfer,
              let source = account(withID: transaction.accountID),
              let destination = account(withID: transaction.destinationAccountID),
              isBankAccount(source),
              !isBankAccount(destination),
              !isFinancialLoanAccount(destination) else { return false }
        return true
    }

    func reportExpenseAmount(_ transaction: LedgerTransaction) -> Decimal {
        transaction.amount
    }

    func reportExpenseAccountID(_ transaction: LedgerTransaction) -> UUID? {
        transaction.accountID
    }

    func loanIncreaseAmount(_ transaction: LedgerTransaction) -> Decimal {
        guard transaction.type == .transfer,
              let source = account(withID: transaction.accountID),
              isBankAccount(account(withID: transaction.destinationAccountID)) else { return 0 }
        if source.group == .payments {
            return paymentLoanIncreaseAmount(transaction)
        }
        return source.nature == .loan ? transaction.amount : 0
    }

    func loanDecreaseAmount(_ transaction: LedgerTransaction) -> Decimal {
        guard transaction.type == .transfer,
              isBankAccount(account(withID: transaction.accountID)),
              isFinancialLoanAccount(account(withID: transaction.destinationAccountID)) else {
            return 0
        }
        return transaction.amount
    }

''',
)

replace_once(
    store,
    '''        return convertedReportAmount(
            reportIncomeAmount(transaction),
            accountID: reportIncomeAccountID(transaction),
            to: destinationCode
        )
''',
    '''        return convertedReportAmount(
            reportIncomeAmount(transaction),
            accountID: reportIncomeConversionAccountID(transaction),
            to: destinationCode
        )
''',
)
replace_once(
    store,
    '''    func convertedReportExpenseAmount(
        _ transaction: LedgerTransaction,
        to destinationCode: String? = nil
    ) -> Decimal? {
        guard transaction.type == .expense else { return nil }
        return convertedReportAmount(
            transaction.amount,
            accountID: transaction.accountID,
            to: destinationCode
        )
    }
''',
    '''    func convertedReportExpenseAmount(
        _ transaction: LedgerTransaction,
        to destinationCode: String? = nil
    ) -> Decimal? {
        guard isReportExpense(transaction) else { return nil }
        return convertedReportAmount(
            reportExpenseAmount(transaction),
            accountID: reportExpenseAccountID(transaction),
            to: destinationCode
        )
    }
''',
)

reports = "DailyLedger/Views/ReportsView.swift"
replace_once(
    reports,
    '''            HStack(alignment: .top, spacing: 12) {
                moneyFlowColumn(
                    title: "Total Money In",
                    color: AppTheme.green,
                    totalValue: totalMoneyIn,
                    primaryTitle: "Income",
                    primaryValue: totals.income,
                    primaryKind: .income,
                    movementTitle: "Loan Increase",
                    movements: loanIncreaseMovements,
                    receivableMovements: receivableCollectionMovements
                )
                moneyFlowColumn(
                    title: "Total Money Out",
                    color: AppTheme.red,
                    totalValue: totalMoneyOut,
                    primaryTitle: "Expenses",
                    primaryValue: totals.expense,
                    primaryKind: .expenses,
                    movementTitle: "Loan Payments",
                    movements: loanPaymentMovements,
                    receivableMovements: []
                )
            }
''',
    '''            HStack(alignment: .top, spacing: 12) {
                moneyFlowColumn(
                    title: "Total Money In",
                    color: AppTheme.green,
                    totalValue: totalMoneyIn,
                    primaryTitle: "Income",
                    primaryValue: totals.income,
                    primaryKind: .income,
                    movementTitle: "Loan Increase",
                    movements: loanIncreaseMovements
                )
                moneyFlowColumn(
                    title: "Total Money Out",
                    color: AppTheme.red,
                    totalValue: totalMoneyOut,
                    primaryTitle: "Expenses",
                    primaryValue: totals.expense,
                    primaryKind: .expenses,
                    movementTitle: "Loan Decrease",
                    movements: loanDecreaseMovements
                )
            }
''',
)
replace_range(
    reports,
    "    private var loanIncreaseMovements: [LoanNetMovement] {\n",
    "    private func moneyFlowColumn(\n",
    r'''    private var loanIncreaseMovements: [LoanNetMovement] {
        financialLoanMovements(increase: true)
    }

    private var loanDecreaseMovements: [LoanNetMovement] {
        financialLoanMovements(increase: false)
    }

    private func financialLoanMovements(increase: Bool) -> [LoanNetMovement] {
        var totalsByCurrency: [String: Decimal] = [:]
        for transaction in store.transactions where selectedInterval.contains(transaction.date) {
            let value = increase
                ? store.loanIncreaseAmount(transaction)
                : store.loanDecreaseAmount(transaction)
            guard value > 0,
                  let source = store.account(withID: transaction.accountID) else { continue }
            totalsByCurrency[source.currencyCode.uppercased(), default: 0] += value
        }
        return movementRows(totalsByCurrency)
    }

    private func movementRows(_ totals: [String: Decimal]) -> [LoanNetMovement] {
        totals.compactMap { currency, amount in
            guard amount > 0 else { return nil }
            return LoanNetMovement(currencyCode: currency, netAmount: amount)
        }.sorted { $0.currencyCode < $1.currencyCode }
    }

    private func convertedMovementTotal(_ movements: [LoanNetMovement]) -> Decimal {
        movements.reduce(Decimal.zero) { total, movement in
            guard let rate = store.fixedReportConversionRate(
                from: movement.currencyCode,
                to: store.currencyCode
            ) else { return total }
            return total + movement.netAmount * rate
        }
    }

    private var totalMoneyIn: Decimal {
        totals.income + convertedMovementTotal(loanIncreaseMovements)
    }

    private var totalMoneyOut: Decimal {
        totals.expense + convertedMovementTotal(loanDecreaseMovements)
    }

''',
)
replace_once(
    reports,
    '''        movementTitle: String,
        movements: [LoanNetMovement],
        receivableMovements: [LoanNetMovement]
    ) -> some View {
''',
    '''        movementTitle: String,
        movements: [LoanNetMovement]
    ) -> some View {
''',
)
replace_once(
    reports,
    '''
            if !receivableMovements.isEmpty {
                ForEach(receivableMovements) { movement in
                    formulaOperator("+", color: color)
                    movementCard(
                        title: "Receivable Collected",
                        movement: movement,
                        icon: "person.crop.circle.badge.checkmark",
                        color: AppTheme.blue
                    )
                }
            }
''',
    "\n",
)


# ---------------------------------------------------------------------------
# SMS auto record. Off = drafts. On = background record only when every mapping
# is unambiguous. Incoming Fawran transfers remain drafts for From/To selection.
# ---------------------------------------------------------------------------
service = "DailyLedger/Services/SMSImportConsoleService.swift"
replace_once(
    service,
    '''struct SMSImportConfiguration: Codable, Equatable {
    var enabled = true
''',
    '''struct SMSImportConfiguration: Codable, Equatable {
    var enabled = true
    var autoRecord = false
''',
)
replace_once(
    service,
    '''        case enabled
        case cardAccountIDs
''',
    '''        case enabled
        case autoRecord
        case cardAccountIDs
''',
)
replace_once(
    service,
    '''        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        cardAccountIDs = try container.decodeIfPresent([String: String].self, forKey: .cardAccountIDs) ?? [:]
''',
    '''        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        autoRecord = try container.decodeIfPresent(Bool.self, forKey: .autoRecord) ?? false
        cardAccountIDs = try container.decodeIfPresent([String: String].self, forKey: .cardAccountIDs) ?? [:]
''',
)

console = "DailyLedger/Views/SMSImportConsoleView.swift"
replace_once(
    console,
    '''                Toggle("Automatic Bank SMS Import", isOn: $configuration.enabled)
''',
    '''                Toggle("SMS Detection", isOn: $configuration.enabled)
                Toggle("Auto Record", isOn: $configuration.autoRecord)
''',
)
# Keep the console compact too.
console_text = read(console)
console_text = console_text.replace(
    'Text("Automatic scans recheck only the latest 10 approved-bank SMS. Manual recovery scans search only the latest 30 incoming SMS rows and reset the automatic timer.")',
    'Text("Auto: latest 10 · Manual: latest 30")'
)
console_text = console_text.replace(
    'Text("The complete original SMS is retained as the description. You may correct it before approval.")',
    'Text("Full SMS description")'
)
write(console, console_text)

source = "RootHideSMSQueue/Sources/main.m"
replace_once(source, 'static NSString *const kDaemonVersion = @"2.1.4";', 'static NSString *const kDaemonVersion = @"2.1.5";')
replace_once(
    source,
    '''        @"enabled": @YES,
        @"cardAccountIDs": @{},
''',
    '''        @"enabled": @YES,
        @"autoRecord": @NO,
        @"cardAccountIDs": @{},
''',
)

auto_helpers = r'''
static BOOL AutomaticRecordDateIsLocked(NSString *isoDate) {
    NSString *container = ApplicationContainer();
    if (!container || isoDate.length == 0) return NO;
    NSString *preferencesPath = [container stringByAppendingPathComponent:
        @"Library/Preferences/com.nextsolution.dailyledger.plist"];
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:preferencesPath];
    if (![preferences[@"AccountingPeriodLockEnabled"] boolValue]) return NO;
    NSTimeInterval lockTimestamp = [preferences[@"AccountingPeriodLockThroughTimestamp"] doubleValue];
    if (lockTimestamp <= 0) return NO;

    NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
    NSDate *transactionDate = [formatter dateFromString:isoDate];
    if (!transactionDate) return NO;
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDate *lockDate = [NSDate dateWithTimeIntervalSince1970:lockTimestamp];
    NSDate *firstOpenDate = [calendar dateByAddingUnit:NSCalendarUnitDay value:1
                                                toDate:[calendar startOfDayForDate:lockDate]
                                               options:0];
    return [transactionDate compare:firstOpenDate] == NSOrderedAscending;
}

static BOOL CompleteDraftAfterAutomaticRecord(NSString *identifier) {
    int descriptor = AcquireDraftLock();
    if (descriptor < 0) return NO;
    BOOL success = NO;
    @try {
        NSMutableArray *drafts = [ReadJSONArray(DraftsPath()) mutableCopy];
        NSIndexSet *matches = [drafts indexesOfObjectsPassingTest:^BOOL(NSDictionary *draft, NSUInteger index, BOOL *stop) {
            return [draft[@"id"] isEqualToString:identifier];
        }];
        if (matches.count > 0) [drafts removeObjectsAtIndexes:matches];
        if (!WriteJSONArray(drafts, DraftsPath())) return NO;

        NSMutableArray *reviewed = [ReadJSONArray(ReviewedIDsPath()) mutableCopy];
        if (![reviewed containsObject:identifier]) [reviewed addObject:identifier];
        success = WriteJSONArray(reviewed, ReviewedIDsPath());
    } @finally {
        ReleaseDraftLock(descriptor);
    }
    return success;
}

static ImportResult AutoRecordParsedEvent(
    NSDictionary *parsed,
    NSString *sourceKey,
    NSString *sender,
    NSDictionary *config
) {
    if (![config[@"autoRecord"] boolValue]) return ImportResultWaitingForMapping;
    if ([parsed[@"kind"] isEqualToString:@"incomingTransfer"]) {
        AddLog(@"info", @"Fawran transfer kept as draft for From/To account review.");
        return ImportResultWaitingForMapping;
    }
    if (AutomaticRecordDateIsLocked(parsed[@"date"])) {
        AddLog(@"warning", @"SMS transaction is inside the locked accounting period and remains a draft.");
        return ImportResultWaitingForMapping;
    }

    NSString *identifier = DeterministicUUID(sourceKey).UUIDString;
    if ([ReadJSONArray(ReviewedIDsPath()) containsObject:identifier]) {
        return ImportResultDuplicate;
    }
    NSString *eventPath = QueueEvent(parsed, sourceKey, sender);
    if (!eventPath) return ImportResultFailed;
    ImportResult result = ImportEvent(eventPath, config);
    if (result == ImportResultImported || result == ImportResultDuplicate) {
        FinishEvent(eventPath);
        CompleteDraftAfterAutomaticRecord(identifier);
        if (result == ImportResultImported) {
            gState[@"totalImported"] = @([gState[@"totalImported"] integerValue] + 1);
            gState[@"lastImportDate"] = ISODate(NSDate.date);
            AddLog(@"success", @"Auto recorded %@ %@ %@ from **%@.",
                parsed[@"kind"], parsed[@"currency"], parsed[@"amount"], parsed[@"cardEnding"]);
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                (__bridge CFStringRef)kDarwinChangeNotification,
                NULL, NULL, true
            );
        }
    }
    return result;
}

'''
replace_once(
    source,
    '''static NSInteger ConfiguredAutomaticScanHours(NSDictionary *config) {
''',
    auto_helpers + '''static NSInteger ConfiguredAutomaticScanHours(NSDictionary *config) {
''',
)
replace_once(
    source,
    '''    NSInteger draftsCreated = 0;
    NSInteger alreadyHandled = 0;
''',
    '''    NSInteger draftsCreated = 0;
    NSInteger autoRecorded = 0;
    NSInteger alreadyHandled = 0;
''',
)
replace_once(
    source,
    '''        DraftResult result = CreateDraft(parsed, sourceKey, sender, rowID);
        if (result == DraftResultCreated) draftsCreated += 1;
        else if (result == DraftResultAlreadyPending || result == DraftResultAlreadyReviewed) alreadyHandled += 1;
        else {
            draftFailures += 1;
            AddLog(@"error", @"Could not save approval draft for SMS row %lld. It will be retried on the next scan.", rowID);
        }
''',
    '''        DraftResult result = CreateDraft(parsed, sourceKey, sender, rowID);
        if (result == DraftResultAlreadyReviewed) {
            alreadyHandled += 1;
        } else if (result == DraftResultCreated || result == DraftResultAlreadyPending) {
            ImportResult automaticResult = AutoRecordParsedEvent(parsed, sourceKey, sender, config);
            if (automaticResult == ImportResultImported) {
                autoRecorded += 1;
            } else if (automaticResult == ImportResultDuplicate && [config[@"autoRecord"] boolValue]) {
                alreadyHandled += 1;
            } else if (result == DraftResultCreated) {
                draftsCreated += 1;
            } else {
                alreadyHandled += 1;
            }
        } else {
            draftFailures += 1;
            AddLog(@"error", @"Could not save approval draft for SMS row %lld. It will be retried on the next scan.", rowID);
        }
''',
)
replace_once(
    source,
    '''        @"%@: read %ld database rows; checked %ld approved-bank SMS; matched %ld transactions; created %ld drafts; already handled %ld; ignored sender %ld; ignored card %ld; unreadable bodies %ld; parse failures %ld; draft failures %ld. Next automatic scan in %ld hour%@.",
''',
    '''        @"%@: read %ld rows; checked %ld bank SMS; matched %ld; auto recorded %ld; created %ld drafts; handled %ld; ignored sender %ld; ignored card %ld; unreadable %ld; parse failures %ld; draft failures %ld. Next scan in %ld hour%@.",
''',
)
replace_once(
    source,
    '''        (long)matched,
        (long)draftsCreated,
        (long)alreadyHandled,
''',
    '''        (long)matched,
        (long)autoRecorded,
        (long)draftsCreated,
        (long)alreadyHandled,
''',
)

for path in ["RootHideSMSQueue/control"]:
    replace_once(path, "Version: 2.1.4", "Version: 2.1.5")
for path in ["RootHideSMSQueue/postinst", "RootHideSMSQueue/layout/DEBIAN/postinst"]:
    replace_once(
        path,
        "Next Ledger SMS Daemon 2.1.4 installation started",
        "Next Ledger SMS Daemon 2.1.5 installation started",
    )


# ---------------------------------------------------------------------------
# Settings: make each top-level section compact and tap-to-open; remove footers
# and long row subtitles. Only one section is expanded at a time.
# ---------------------------------------------------------------------------
settings = "DailyLedger/Views/SettingsView.swift"
settings_text = read(settings)
settings_text = settings_text.replace(
    '    @State private var showingSMSStatus = true\n',
    '    @State private var showingSMSStatus = true\n    @State private var expandedSettingsSection: String?\n',
    1,
)
if "expandedSettingsSection" not in settings_text:
    # Later patches can remove showingSMSStatus; use the stable theme property.
    settings_text = settings_text.replace(
        '    @AppStorage("DailyLedgerVisualTheme") private var visualTheme = AppVisualTheme.glass.rawValue\n',
        '    @AppStorage("DailyLedgerVisualTheme") private var visualTheme = AppVisualTheme.glass.rawValue\n    @State private var expandedSettingsSection: String?\n',
        1,
    )

# Remove subtitles from SettingsRow calls while retaining titles/icons.
settings_text = re.sub(r'(?m)^(\s*)subtitle:\s*(?:"(?:\\.|[^"\\])*"|[^,\n]+),\s*$', r'\1subtitle: "",', settings_text)
settings_text = settings_text.replace(
    'Text("Transactions on or before this date are protected")',
    'Text("Locked through selected date")'
)


def matching_brace(text: str, opening: int) -> int:
    depth = 0
    in_string = False
    escaped = False
    index = opening
    while index < len(text):
        ch = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
        else:
            if ch == '"':
                in_string = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return index
        index += 1
    raise RuntimeError("Unbalanced Swift braces while compacting Settings")


list_marker = "            List {"
list_start = settings_text.find(list_marker)
if list_start < 0:
    raise RuntimeError("Settings List marker not found")
list_open = settings_text.find("{", list_start)
list_close = matching_brace(settings_text, list_open)
body = settings_text[list_open + 1:list_close]
section_starts = [match.start() for match in re.finditer(r'(?m)^                Section(?:\s*\(|\s*\{)', body)]
if len(section_starts) < 5:
    raise RuntimeError(f"Expected multiple Settings sections, found {len(section_starts)}")

replacements = []
for position, start in enumerate(section_starts):
    end = section_starts[position + 1] if position + 1 < len(section_starts) else len(body)
    chunk = body[start:end]
    first_line_end = chunk.find("\n")
    first_line = chunk[:first_line_end] if first_line_end >= 0 else chunk
    content_open = chunk.find("{")
    if content_open < 0:
        continue
    content_close = matching_brace(chunk, content_open)
    content = chunk[content_open + 1:content_close]
    tail = chunk[content_close + 1:]

    title_match = re.search(r'Label\("([^"]+)",\s*systemImage:\s*"([^"]+)"\)', tail, re.S)
    if title_match:
        title, icon = title_match.group(1), title_match.group(2)
    else:
        direct = re.search(r'Section\("([^"]+)"\)', first_line)
        title = direct.group(1) if direct else f"Settings {position + 1}"
        icon = "gearshape.fill"

    # AI already had a nested disclosure. Keep its controls but remove the extra tap.
    if title == "AI" and "DisclosureGroup(isExpanded: $showingAISettings)" in content:
        inner_open = content.find("{", content.find("DisclosureGroup(isExpanded: $showingAISettings)"))
        inner_close = matching_brace(content, inner_open)
        content = content[inner_open + 1:inner_close]

    content_lines = content.splitlines()
    adjusted = []
    for line in content_lines:
        adjusted.append("    " + line if line.strip() else line)
    adjusted_content = "\n".join(adjusted).rstrip()
    safe_title = title.replace('"', '\\"')
    replacement = (
        f'                Section {{\n'
        f'                    DisclosureGroup(isExpanded: settingsSectionBinding("{safe_title}")) {{'
        f'{adjusted_content}\n'
        f'                    }} label: {{\n'
        f'                        Label("{safe_title}", systemImage: "{icon}")\n'
        f'                            .font(.headline)\n'
        f'                    }}\n'
        f'                }}\n\n'
    )
    replacements.append((start, end, replacement))

for start, end, replacement in reversed(replacements):
    body = body[:start] + replacement + body[end:]
settings_text = settings_text[:list_open + 1] + body + settings_text[list_close:]

binding_code = r'''    private func settingsSectionBinding(_ title: String) -> Binding<Bool> {
        Binding(
            get: { expandedSettingsSection == title },
            set: { expandedSettingsSection = $0 ? title : nil }
        )
    }

'''
backup_marker = "    private var backupDocument: BackupDocument {\n"
if backup_marker not in settings_text:
    raise RuntimeError("Settings backup marker not found")
settings_text = settings_text.replace(backup_marker, binding_code + backup_marker, 1)

# Hide blank subtitles without leaving empty vertical space.
settings_text = settings_text.replace(
    '''                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
''',
    '''                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
''',
    1,
)
write(settings, settings_text)

print("Fixed bank/loan flow classification, removed Receivables from Financial Summary, added SMS Auto Record, and compacted Settings sections.")
