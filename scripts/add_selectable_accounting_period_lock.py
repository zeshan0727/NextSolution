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
        raise RuntimeError(f"Expected one match in {path}, found {count}: {old[:200]!r}")
    write(path, text.replace(old, new, 1))


write(
    "DailyLedger/Services/AccountingPeriodLock.swift",
    r'''import Foundation

enum AccountingPeriodLock {
    static let enabledKey = "AccountingPeriodLockEnabled"
    static let timestampKey = "AccountingPeriodLockThroughTimestamp"

    static var lockedThroughDate: Date? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: enabledKey) else { return nil }
        let timestamp = defaults.double(forKey: timestampKey)
        guard timestamp > 0 else { return nil }
        return Calendar.current.startOfDay(for: Date(timeIntervalSince1970: timestamp))
    }

    static func isLocked(_ date: Date) -> Bool {
        guard let lockedThroughDate,
              let firstOpenDay = Calendar.current.date(
                byAdding: .day,
                value: 1,
                to: lockedThroughDate
              ) else { return false }
        return date < firstOpenDay
    }

    static func blockedMessage(action: String, date: Date) -> String {
        guard let lockedThroughDate else {
            return "The accounting period is locked."
        }
        return "Cannot \(action) the transaction dated \(date.formatted(date: .abbreviated, time: .omitted)). The accounting period is locked through \(lockedThroughDate.formatted(date: .abbreviated, time: .omitted))."
    }
}
''',
)

settings = "DailyLedger/Views/SettingsView.swift"
replace_once(
    settings,
    '''    @AppStorage("AccountingPeriodStartDay") private var accountingPeriodStartDay = 26

    private let currencies = ["QAR", "USD", "GBP", "EUR", "AED", "SAR", "PKR", "INR"]
''',
    '''    @AppStorage("AccountingPeriodStartDay") private var accountingPeriodStartDay = 26
    @AppStorage("AccountingPeriodLockEnabled") private var accountingPeriodLockEnabled = false
    @AppStorage("AccountingPeriodLockThroughTimestamp") private var accountingPeriodLockThroughTimestamp = 0.0

    private let currencies = ["QAR", "USD", "GBP", "EUR", "AED", "SAR", "PKR", "INR"]
''',
)
replace_once(
    settings,
    '''                    LabeledContent("Default Cycle", value: accountingPeriodLabel)
                } header: {
                    Label("Accounting Period", systemImage: "calendar.badge.clock")
                } footer: {
                    Text("Reports can use this cycle automatically. A start day of 26 creates a period from the 26th through the 25th of the next month.")
                }
''',
    '''                    LabeledContent("Default Cycle", value: accountingPeriodLabel)
                    Divider()
                    Toggle("Enable Period Lock", isOn: accountingPeriodLockBinding)
                    if accountingPeriodLockEnabled {
                        DatePicker(
                            "Lock Through Date",
                            selection: accountingPeriodLockDateBinding,
                            displayedComponents: .date
                        )
                        Label(
                            "Transactions on or before this date are protected",
                            systemImage: "lock.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("Accounting Period", systemImage: "calendar.badge.clock")
                } footer: {
                    Text("Reports can use the selected accounting cycle automatically. The optional lock date can be any calendar date. When enabled, transactions dated on or before that date cannot be added, approved from SMS drafts, edited, split, refunded on a locked date, or deleted.")
                }
''',
)
replace_once(
    settings,
    '''    private var accountingPeriodLabel: String {
''',
    '''    private var accountingPeriodLockBinding: Binding<Bool> {
        Binding(
            get: { accountingPeriodLockEnabled },
            set: { enabled in
                accountingPeriodLockEnabled = enabled
                if enabled && accountingPeriodLockThroughTimestamp <= 0 {
                    accountingPeriodLockThroughTimestamp = Calendar.current
                        .startOfDay(for: Date())
                        .timeIntervalSince1970
                }
            }
        )
    }

    private var accountingPeriodLockDateBinding: Binding<Date> {
        Binding(
            get: {
                guard accountingPeriodLockThroughTimestamp > 0 else {
                    return Calendar.current.startOfDay(for: Date())
                }
                return Date(timeIntervalSince1970: accountingPeriodLockThroughTimestamp)
            },
            set: { date in
                accountingPeriodLockThroughTimestamp = Calendar.current
                    .startOfDay(for: date)
                    .timeIntervalSince1970
            }
        )
    }

    private var accountingPeriodLabel: String {
''',
)

store = "DailyLedger/Services/LedgerStore.swift"
replace_once(
    store,
    '''    var currencyCode: String { settings.currencyCode }
    var defaultAccountID: UUID? { settings.defaultAccountID ?? accounts.first?.id }
''',
    '''    var currencyCode: String { settings.currencyCode }
    var defaultAccountID: UUID? { settings.defaultAccountID ?? accounts.first?.id }

    private func requireOpenPeriod(_ date: Date, action: String) -> Bool {
        guard !AccountingPeriodLock.isLocked(date) else {
            errorMessage = AccountingPeriodLock.blockedMessage(action: action, date: date)
            return false
        }
        return true
    }
''',
)
replace_once(
    store,
    '''    ) {
        let cleanedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
''',
    '''    ) {
        guard requireOpenPeriod(date, action: "record") else { return }
        let cleanedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
''',
)
replace_once(
    store,
    '''    ) {
        guard firstAccountID != secondAccountID, firstAmount > 0, secondAmount > 0,
''',
    '''    ) {
        guard requireOpenPeriod(transaction.date, action: "split") else { return }
        guard firstAccountID != secondAccountID, firstAmount > 0, secondAmount > 0,
''',
)
replace_once(
    store,
    '''    ) {
        guard transaction.type == .expense, firstAmount > 0, secondAmount > 0,
''',
    '''    ) {
        guard requireOpenPeriod(transaction.date, action: "split") else { return }
        guard transaction.type == .expense, firstAmount > 0, secondAmount > 0,
''',
)
replace_once(
    store,
    '''    ) {
        guard sourceID != destinationID else {
''',
    '''    ) {
        guard requireOpenPeriod(date, action: "record") else { return }
        guard sourceID != destinationID else {
''',
)
replace_once(
    store,
    '''    ) -> Bool {
        guard transaction.type != .transfer, transaction.refundOfTransactionID == nil else {
''',
    '''    ) -> Bool {
        guard requireOpenPeriod(date, action: "record a refund for") else { return false }
        guard transaction.type != .transfer, transaction.refundOfTransactionID == nil else {
''',
)
replace_once(
    store,
    '''    func delete(_ transaction: LedgerTransaction) {
        do {
''',
    '''    func delete(_ transaction: LedgerTransaction) {
        guard requireOpenPeriod(transaction.date, action: "delete") else { return }
        do {
''',
)
replace_once(
    store,
    '''    func update(_ transaction: LedgerTransaction) {
        var found = false
''',
    '''    func update(_ transaction: LedgerTransaction) {
        if let original = transactions.first(where: { $0.id == transaction.id }),
           !requireOpenPeriod(original.date, action: "update") {
            return
        }
        guard requireOpenPeriod(transaction.date, action: "move or update") else { return }
        var found = false
''',
)
replace_once(
    store,
    '''    func approveSMSDraft(_ draft: SMSImportDraft, configuration: SMSImportConfiguration) -> Bool {
        if transactions.contains(where: { $0.id == draft.id }) { return true }
''',
    '''    func approveSMSDraft(_ draft: SMSImportDraft, configuration: SMSImportConfiguration) -> Bool {
        guard requireOpenPeriod(draft.date, action: "approve") else { return false }
        if transactions.contains(where: { $0.id == draft.id }) { return true }
''',
)

print("Added an optional, arbitrary inclusive accounting lock date across transaction recording and mutation paths.")
