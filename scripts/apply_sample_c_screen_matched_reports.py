from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match in {path}, found {count}: {old[:180]!r}")
    write(path, text.replace(old, new, 1))


service = "DailyLedger/Services/ProfessionalReportExportService.swift"
button = "DailyLedger/Views/ReportDownloadButton.swift"
reports = "DailyLedger/Views/ReportsView.swift"

# Do not generate empty currency pages.
replace_once(
    service,
    '''            var rows: [ProfessionalReportRow] = []
            for section in BalanceSheetSection.allCases {
''',
    '''            guard !lines.isEmpty else { continue }

            var rows: [ProfessionalReportRow] = []
            for section in BalanceSheetSection.allCases {
''',
)

# Build a document from exactly the transactions visible in the active report.
insert_anchor = '''    private static func financialSummary(
'''
screen_builder = r'''    static func buildScreenMatched(
        type: ProfessionalReportType,
        startDate: Date,
        endDate: Date,
        visibleTransactions: [LedgerTransaction],
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: min(startDate, endDate))
        let endDay = calendar.startOfDay(for: max(startDate, endDate))
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        let interval = DateInterval(start: start, end: endExclusive)
        let items = visibleTransactions.filter { interval.contains($0.date) }

        switch type {
        case .incomeTransactions, .expenseTransactions:
            let isIncome = type == .incomeTransactions
            let title = isIncome ? "Income Report" : "Expense Report"
            let rows = items.sorted { $0.date < $1.date }.map { transaction -> ProfessionalReportRow in
                let accountID = isIncome ? store.reportIncomeAccountID(transaction) : transaction.accountID
                let account = store.account(withID: accountID)
                let currency = account?.currencyCode.uppercased() ?? "QAR"
                let amount = isIncome ? store.reportIncomeAmount(transaction) : transaction.amount
                let qarEquivalent: ProfessionalReportCell = currency == "QAR"
                    ? .number(amount)
                    : currency == "PKR" ? .number(amount / pkrPerQAR) : .text("—")
                return ProfessionalReportRow([
                    .text(shortDate(transaction.date)),
                    .text(account?.name ?? "Unassigned"),
                    .text(transaction.category),
                    .text(transaction.vendor?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "—"),
                    .number(amount),
                    .text(currency),
                    qarEquivalent
                ])
            }
            return ProfessionalReportDocument(
                title: title,
                subtitle: "Same dates, accounts and filtered transactions shown on screen",
                periodText: periodText(interval),
                generatedAt: Date(),
                tables: [ProfessionalReportTable(
                    title: title,
                    subtitle: "Screen-matched transaction detail",
                    columns: ["Date", "Account", "Category", "Vendor", "Amount", "Currency", "QAR Eq."],
                    rows: rows.isEmpty ? [ProfessionalReportRow([.text("—"), .text("No transactions"), .text("—"), .text("—"), .number(0), .text("QAR"), .number(0)])] : rows
                )],
                notes: nativeCurrencyNotes
            )
        case .transfers:
            let rows = items.sorted { $0.date < $1.date }.map { transaction -> ProfessionalReportRow in
                let source = store.account(withID: transaction.accountID)
                let destination = store.account(withID: transaction.destinationAccountID)
                let currency = source?.currencyCode.uppercased() ?? "QAR"
                let qarEquivalent: ProfessionalReportCell = currency == "QAR"
                    ? .number(transaction.amount)
                    : currency == "PKR" ? .number(transaction.amount / pkrPerQAR) : .text("—")
                return ProfessionalReportRow([
                    .text(shortDate(transaction.date)),
                    .text(source?.name ?? "Unassigned"),
                    .text(destination?.name ?? "Unassigned"),
                    .number(transaction.amount),
                    .text(currency),
                    qarEquivalent
                ])
            }
            return ProfessionalReportDocument(
                title: "Loans / Transfers",
                subtitle: "Same transfers currently shown on screen",
                periodText: periodText(interval),
                generatedAt: Date(),
                tables: [ProfessionalReportTable(
                    title: "Transfer Detail",
                    subtitle: "Screen-matched accounts and dates",
                    columns: ["Date", "From", "To", "Amount", "Currency", "QAR Eq."],
                    rows: rows.isEmpty ? [ProfessionalReportRow([.text("—"), .text("No transfers"), .text("—"), .number(0), .text("QAR"), .number(0)])] : rows
                )],
                notes: nativeCurrencyNotes
            )
        case .categorySummary:
            var totals: [String: (qar: Decimal, pkr: Decimal)] = [:]
            for transaction in items where transaction.type == .expense {
                let currency = store.account(withID: transaction.accountID)?.currencyCode.uppercased() ?? "QAR"
                var value = totals[transaction.category] ?? (0, 0)
                if currency == "PKR" { value.pkr += transaction.amount }
                else if currency == "QAR" { value.qar += transaction.amount }
                totals[transaction.category] = value
            }
            let rows = totals.keys.sorted(by: localizedSort).map { category -> ProfessionalReportRow in
                let value = totals[category] ?? (0, 0)
                let pkrQAR = value.pkr / pkrPerQAR
                return ProfessionalReportRow([.text(category), .number(value.qar), .number(value.pkr), .number(pkrQAR), .number(value.qar + pkrQAR)])
            }
            return ProfessionalReportDocument(
                title: "Category Report",
                subtitle: "Same categories and transactions shown on screen",
                periodText: periodText(interval),
                generatedAt: Date(),
                tables: [ProfessionalReportTable(
                    title: "Expense Categories",
                    subtitle: "Screen-matched category totals",
                    columns: ["Category", "QAR", "PKR", "PKR in QAR", "Consolidated QAR"],
                    rows: rows.isEmpty ? [ProfessionalReportRow([.text("No expenses"), .number(0), .number(0), .number(0), .number(0)])] : rows
                )],
                notes: nativeCurrencyNotes
            )
        default:
            return build(type: type, startDate: startDate, endDate: endDate, store: store)
        }
    }

'''
replace_once(service, insert_anchor, screen_builder + insert_anchor)

# Sample C visual system: green, compact and fully wrapped.
text = read(service)
text = text.replace('UIColor(red: 0.22, green: 0.12, blue: 0.48, alpha: 1)', 'UIColor(red: 0.125, green: 0.353, blue: 0.278, alpha: 1)')
text = text.replace('UIColor(red: 0.94, green: 0.92, blue: 0.98, alpha: 1)', 'UIColor(red: 0.925, green: 0.969, blue: 0.945, alpha: 1)')
text = text.replace('UIColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1)', 'UIColor(red: 0.910, green: 0.953, blue: 0.929, alpha: 1)')
text = text.replace('style.lineBreakMode = .byTruncatingTail', 'style.lineBreakMode = .byWordWrapping')
text = text.replace('options: [.usesLineFragmentOrigin, .usesFontLeading]', 'options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine]')
# More room for labels in common table shapes.
text = text.replace('case 5: ratios = [0.10, 0.34, 0.18, 0.18, 0.20]', 'case 5: ratios = [0.13, 0.39, 0.16, 0.16, 0.16]')
text = text.replace('case 6: ratios = [0.34, 0.132, 0.132, 0.132, 0.132, 0.142]', 'case 6: ratios = [0.40, 0.12, 0.12, 0.12, 0.12, 0.12]')
text = text.replace('case 8: ratios = [0.10, 0.16, 0.24, 0.10, 0.10, 0.10, 0.10, 0.10]', 'case 8: ratios = [0.11, 0.15, 0.28, 0.09, 0.09, 0.09, 0.09, 0.10]')
# Increase row height so wrapped labels remain readable.
text = text.replace('let rowHeight: CGFloat = table.columns.count >= 8 ? 27 : 22', 'let rowHeight: CGFloat = table.columns.count >= 8 ? 34 : 29')
write(service, text)

# Let the download button receive the exact visible transactions.
replace_once(
    button,
    '''    let type: ProfessionalReportType
    let startDate: Date
    let endDate: Date
''',
    '''    let type: ProfessionalReportType
    let startDate: Date
    let endDate: Date
    var visibleTransactions: [LedgerTransaction]? = nil
''',
)
replace_once(
    button,
    '''        let document = ProfessionalReportBuilder.build(
            type: type,
            startDate: startDate,
            endDate: endDate,
            store: store
        )
''',
    '''        let document: ProfessionalReportDocument
        if let visibleTransactions {
            document = ProfessionalReportBuilder.buildScreenMatched(
                type: type,
                startDate: startDate,
                endDate: endDate,
                visibleTransactions: visibleTransactions,
                store: store
            )
        } else {
            document = ProfessionalReportBuilder.build(
                type: type,
                startDate: startDate,
                endDate: endDate,
                store: store
            )
        }
''',
)

# Toolbar export now uses exactly the visible transactions and active custom date.
replace_once(
    reports,
    '''                    ReportDownloadButton(
                        type: kind.exportType,
                        startDate: selectedInterval.start,
                        endDate: reportExportEndDate
                    )
''',
    '''                    ReportDownloadButton(
                        type: kind.exportType,
                        startDate: selectedInterval.start,
                        endDate: reportExportEndDate,
                        visibleTransactions: selectedTransactions
                    )
''',
)

print("Applied Sample C report style, full-text layout, empty-currency cleanup and screen-matched exports.")
