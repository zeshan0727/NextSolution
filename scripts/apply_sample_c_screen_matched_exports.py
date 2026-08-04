from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def write(relative: str, content: str) -> None:
    (ROOT / relative).write_text(content, encoding="utf-8")


def replace_once(relative: str, old: str, new: str) -> None:
    text = read(relative)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match in {relative}, found {count}: {old[:220]!r}")
    write(relative, text.replace(old, new, 1))


service = "DailyLedger/Services/ProfessionalReportExportService.swift"
reports = "DailyLedger/Views/ReportsView.swift"
button = "DailyLedger/Views/ReportDownloadButton.swift"

# Add a scope that preserves the report currently being reviewed.
replace_once(
    service,
    '''struct ProfessionalReportDocument {
    let title: String
    let subtitle: String
    let periodText: String
    let generatedAt: Date
    let tables: [ProfessionalReportTable]
    let notes: [String]
}
''',
    '''struct ProfessionalReportDocument {
    let title: String
    let subtitle: String
    let periodText: String
    let generatedAt: Date
    let tables: [ProfessionalReportTable]
    let notes: [String]
}

struct ProfessionalReportScope {
    var transactionIDs: Set<UUID> = []
    var accountIDs: Set<UUID> = []
    var currencyCode: String? = nil
    var reportTitle: String? = nil

    var isEmpty: Bool {
        transactionIDs.isEmpty && accountIDs.isEmpty && currencyCode == nil && reportTitle == nil
    }
}
''',
)

replace_once(
    service,
    '''    static func build(
        type: ProfessionalReportType,
        startDate: Date,
        endDate: Date,
        store: LedgerStore
    ) -> ProfessionalReportDocument {
''',
    '''    static func build(
        type: ProfessionalReportType,
        startDate: Date,
        endDate: Date,
        store: LedgerStore,
        scope: ProfessionalReportScope = ProfessionalReportScope()
    ) -> ProfessionalReportDocument {
''',
)

replace_once(
    service,
    '''        let interval = DateInterval(start: start, end: endExclusive)

        let document: ProfessionalReportDocument
''',
    '''        let interval = DateInterval(start: start, end: endExclusive)

        if !scope.isEmpty {
            return scopedDocument(
                type: type,
                interval: interval,
                endDay: endDay,
                store: store,
                scope: scope
            )
        }

        let document: ProfessionalReportDocument
''',
)

scoped_helpers = r'''    private static func scopedDocument(
        type: ProfessionalReportType,
        interval: DateInterval,
        endDay: Date,
        store: LedgerStore,
        scope: ProfessionalReportScope
    ) -> ProfessionalReportDocument {
        let transactions = store.transactions.filter { transaction in
            guard interval.contains(transaction.date) else { return false }
            if !scope.transactionIDs.isEmpty, !scope.transactionIDs.contains(transaction.id) {
                return false
            }
            if !scope.accountIDs.isEmpty {
                let source = transaction.accountID ?? LedgerAccount.legacyMainID
                let destination = transaction.destinationAccountID ?? LedgerAccount.legacyMainID
                let incomeAccount = store.reportIncomeAccountID(transaction) ?? LedgerAccount.legacyMainID
                if !scope.accountIDs.contains(source) &&
                    !scope.accountIDs.contains(destination) &&
                    !scope.accountIDs.contains(incomeAccount) {
                    return false
                }
            }
            if let currency = scope.currencyCode?.uppercased() {
                let accountID = store.isReportIncome(transaction)
                    ? store.reportIncomeAccountID(transaction)
                    : transaction.accountID
                if store.account(withID: accountID)?.currencyCode.uppercased() != currency {
                    return false
                }
            }
            return true
        }

        let accounts = store.activeAccounts.filter { account in
            if !scope.accountIDs.isEmpty, !scope.accountIDs.contains(account.id) { return false }
            if let currency = scope.currencyCode?.uppercased(),
               account.currencyCode.uppercased() != currency { return false }
            return true
        }

        let base: ProfessionalReportDocument
        switch type {
        case .financialSummary:
            base = scopedFinancialSummary(interval: interval, transactions: transactions, store: store)
        case .incomeTransactions:
            base = scopedTransactionReport(isIncome: true, interval: interval, transactions: transactions, store: store)
        case .expenseTransactions:
            base = scopedTransactionReport(isIncome: false, interval: interval, transactions: transactions, store: store)
        case .transfers:
            base = scopedTransferReport(interval: interval, transactions: transactions, store: store)
        case .categorySummary:
            base = scopedCategoryReport(interval: interval, transactions: transactions, store: store)
        case .incomeStatement:
            base = scopedIncomeStatement(interval: interval, transactions: transactions, store: store)
        case .balanceSheet:
            base = scopedBalanceSheet(interval: interval, accounts: accounts, store: store)
        case .payablesAging:
            base = agingReport(isPayable: true, detailed: true, asOf: endDay, store: store)
        case .payablesSummary:
            base = agingReport(isPayable: true, detailed: false, asOf: endDay, store: store)
        case .receivablesAging:
            base = agingReport(isPayable: false, detailed: true, asOf: endDay, store: store)
        case .receivablesSummary:
            base = agingReport(isPayable: false, detailed: false, asOf: endDay, store: store)
        }

        let overview = scopedOverview(
            type: type,
            interval: interval,
            transactions: transactions,
            accounts: accounts,
            store: store
        )
        return ProfessionalReportDocument(
            title: scope.reportTitle ?? base.title,
            subtitle: base.subtitle,
            periodText: base.periodText,
            generatedAt: base.generatedAt,
            tables: (overview.map { [$0] } ?? []) + base.tables,
            notes: base.notes
        )
    }

    private static func scopedCurrencies(
        _ transactions: [LedgerTransaction],
        store: LedgerStore
    ) -> [String] {
        let values = transactions.compactMap { transaction -> String? in
            let accountID = store.isReportIncome(transaction)
                ? store.reportIncomeAccountID(transaction)
                : transaction.accountID
            return store.account(withID: accountID)?.currencyCode.uppercased()
        }
        return Array(Set(values)).sorted()
    }

    private static func scopedFinancialSummary(
        interval: DateInterval,
        transactions: [LedgerTransaction],
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        var tables: [ProfessionalReportTable] = []
        for currency in scopedCurrencies(transactions, store: store) {
            let incomeItems = transactions.filter {
                store.isReportIncome($0) &&
                    store.account(withID: store.reportIncomeAccountID($0))?.currencyCode.uppercased() == currency
            }
            let expenseItems = transactions.filter {
                $0.type == .expense &&
                    store.account(withID: $0.accountID)?.currencyCode.uppercased() == currency
            }
            let income = incomeItems.reduce(Decimal.zero) { $0 + store.reportIncomeAmount($1) }
            let expense = expenseItems.reduce(Decimal.zero) { $0 + $1.amount }
            guard income != 0 || expense != 0 else { continue }
            tables.append(ProfessionalReportTable(
                title: "Financial Summary — \(currency)",
                subtitle: "Reviewed transactions only",
                columns: ["Metric", "Amount", "Transactions"],
                rows: [
                    ProfessionalReportRow([.text("Income"), .number(income), .text("\(incomeItems.count)")]),
                    ProfessionalReportRow([.text("Expenses"), .number(expense), .text("\(expenseItems.count)")]),
                    ProfessionalReportRow([.text("Net Result"), .number(income - expense), .text("\(incomeItems.count + expenseItems.count)")], emphasis: .total)
                ]
            ))
        }
        return ProfessionalReportDocument(
            title: "Financial Summary",
            subtitle: "Same period, currency and filters currently being reviewed",
            periodText: periodText(interval),
            generatedAt: Date(),
            tables: tables,
            notes: screenMatchedNotes
        )
    }

    private static func scopedTransactionReport(
        isIncome: Bool,
        interval: DateInterval,
        transactions: [LedgerTransaction],
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        let items = transactions.filter { isIncome ? store.isReportIncome($0) : $0.type == .expense }
            .sorted { $0.date < $1.date }
        var rows = items.map { transaction -> ProfessionalReportRow in
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
                .text(transaction.vendor?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? transaction.vendor! : "—"),
                .number(amount),
                .text(currency),
                qarEquivalent
            ])
        }
        if rows.isEmpty {
            rows = [ProfessionalReportRow([.text("No reviewed transactions"), .text(""), .text(""), .text(""), .number(0), .text(""), .number(0)])]
        }
        let title = isIncome ? "Income Report" : "Expense Report"
        return ProfessionalReportDocument(
            title: title,
            subtitle: "Same transactions currently visible in the report",
            periodText: periodText(interval),
            generatedAt: Date(),
            tables: [ProfessionalReportTable(
                title: title,
                subtitle: "Native amount and QAR equivalent",
                columns: ["Date", "Account", "Category", "Vendor", "Amount", "Currency", "QAR Equivalent"],
                rows: rows
            )],
            notes: screenMatchedNotes
        )
    }

    private static func scopedTransferReport(
        interval: DateInterval,
        transactions: [LedgerTransaction],
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        let items = transactions.filter { $0.type == .transfer }.sorted { $0.date < $1.date }
        var rows = items.map { transaction -> ProfessionalReportRow in
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
        if rows.isEmpty {
            rows = [ProfessionalReportRow([.text("No reviewed transfers"), .text(""), .text(""), .number(0), .text(""), .number(0)])]
        }
        return ProfessionalReportDocument(
            title: "Loans / Transfers",
            subtitle: "Same transfers currently visible in the report",
            periodText: periodText(interval),
            generatedAt: Date(),
            tables: [ProfessionalReportTable(
                title: "Transfer Detail",
                subtitle: "Source, destination and QAR equivalent",
                columns: ["Date", "From Account", "To Account", "Amount", "Currency", "QAR Equivalent"],
                rows: rows
            )],
            notes: screenMatchedNotes
        )
    }

    private static func scopedCategoryReport(
        interval: DateInterval,
        transactions: [LedgerTransaction],
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        var totals: [String: (qar: Decimal, pkr: Decimal)] = [:]
        for transaction in transactions where transaction.type == .expense {
            let currency = store.account(withID: transaction.accountID)?.currencyCode.uppercased() ?? "QAR"
            var value = totals[transaction.category] ?? (0, 0)
            if currency == "PKR" { value.pkr += transaction.amount }
            else if currency == "QAR" { value.qar += transaction.amount }
            totals[transaction.category] = value
        }
        let rows = totals.keys.sorted(by: localizedSort).map { category -> ProfessionalReportRow in
            let value = totals[category] ?? (0, 0)
            let pkrInQAR = value.pkr / pkrPerQAR
            return ProfessionalReportRow([
                .text(category), .number(value.qar), .number(value.pkr), .number(pkrInQAR), .number(value.qar + pkrInQAR)
            ])
        }
        return ProfessionalReportDocument(
            title: "Category Report",
            subtitle: "Same categories currently visible in the report",
            periodText: periodText(interval),
            generatedAt: Date(),
            tables: [ProfessionalReportTable(
                title: "Expense Categories",
                subtitle: "QAR, PKR and consolidated QAR",
                columns: ["Category", "QAR", "PKR", "PKR in QAR", "Consolidated QAR"],
                rows: rows
            )],
            notes: screenMatchedNotes
        )
    }

    private static func scopedIncomeStatement(
        interval: DateInterval,
        transactions: [LedgerTransaction],
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        var tables: [ProfessionalReportTable] = []
        for currency in scopedCurrencies(transactions, store: store) {
            var revenue: [String: Decimal] = [:]
            var expenses: [String: Decimal] = [:]
            for transaction in transactions {
                if store.isReportIncome(transaction),
                   store.account(withID: store.reportIncomeAccountID(transaction))?.currencyCode.uppercased() == currency {
                    revenue[transaction.category, default: 0] += store.reportIncomeAmount(transaction)
                } else if transaction.type == .expense,
                          store.account(withID: transaction.accountID)?.currencyCode.uppercased() == currency {
                    expenses[transaction.category, default: 0] += transaction.amount
                }
            }
            let totalRevenue = revenue.values.reduce(Decimal.zero, +)
            let totalExpenses = expenses.values.reduce(Decimal.zero, +)
            guard totalRevenue != 0 || totalExpenses != 0 else { continue }
            var rows: [ProfessionalReportRow] = [ProfessionalReportRow([.text("REVENUE"), .text("")], emphasis: .section)]
            rows += revenue.keys.sorted(by: localizedSort).map { ProfessionalReportRow([.text($0), .number(revenue[$0, default: 0])]) }
            rows.append(ProfessionalReportRow([.text("Total Revenue"), .number(totalRevenue)], emphasis: .subtotal))
            rows.append(ProfessionalReportRow([.text("EXPENSES"), .text("")], emphasis: .section))
            rows += expenses.keys.sorted(by: localizedSort).map { ProfessionalReportRow([.text($0), .number(expenses[$0, default: 0])]) }
            rows.append(ProfessionalReportRow([.text("Total Expenses"), .number(totalExpenses)], emphasis: .subtotal))
            rows.append(ProfessionalReportRow([
                .text(totalRevenue >= totalExpenses ? "Net Profit" : "Net Loss"),
                .number(totalRevenue - totalExpenses)
            ], emphasis: .total))
            tables.append(ProfessionalReportTable(
                title: "Income Statement — \(currency)",
                subtitle: "Reviewed categories in native \(currency)",
                columns: ["Category", "Amount"],
                rows: rows
            ))
        }
        return ProfessionalReportDocument(
            title: "Income Statement",
            subtitle: "Revenue, expenses and profit or loss",
            periodText: periodText(interval),
            generatedAt: Date(),
            tables: tables,
            notes: screenMatchedNotes
        )
    }

    private static func scopedBalanceSheet(
        interval: DateInterval,
        accounts: [LedgerAccount],
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        var tables: [ProfessionalReportTable] = []
        for currency in Array(Set(accounts.map { $0.currencyCode.uppercased() })).sorted() {
            let lines = accounts.filter { $0.currencyCode.uppercased() == currency }.compactMap { account -> AccountBalanceLine? in
                let opening = store.combinedBalance(for: [account], before: interval.start)
                let closing = store.combinedBalance(for: [account], before: interval.end)
                let movement = closing - opening
                guard opening != 0 || movement != 0 || closing != 0 else { return nil }
                return AccountBalanceLine(account: account, opening: opening, movement: movement, closing: closing, section: balanceSection(account: account, closing: closing))
            }
            guard !lines.isEmpty else { continue }
            var rows: [ProfessionalReportRow] = []
            for section in BalanceSheetSection.allCases {
                let sectionLines = lines.filter { $0.section == section }.sorted { localizedSort($0.account.name, $1.account.name) }
                guard !sectionLines.isEmpty else { continue }
                rows.append(ProfessionalReportRow([.text(""), .text(section.rawValue), .text(""), .text(""), .text("")], emphasis: .section))
                for line in sectionLines {
                    let multiplier: Decimal = section.isLiability ? -1 : 1
                    rows.append(ProfessionalReportRow([
                        .text(chartCodeText(line.account)), .text(line.account.name),
                        .number(line.opening * multiplier), .number(line.movement * multiplier), .number(line.closing * multiplier)
                    ]))
                }
                let multiplier: Decimal = section.isLiability ? -1 : 1
                rows.append(ProfessionalReportRow([
                    .text(""), .text("Total \(section.rawValue)"),
                    .number(sectionLines.reduce(0) { $0 + $1.opening } * multiplier),
                    .number(sectionLines.reduce(0) { $0 + $1.movement } * multiplier),
                    .number(sectionLines.reduce(0) { $0 + $1.closing } * multiplier)
                ], emphasis: .subtotal))
            }
            tables.append(ProfessionalReportTable(
                title: "Balance Sheet Detail — \(currency)",
                subtitle: "Selected accounts only",
                columns: ["Code", "Account", "Opening", "Movement", "Closing"],
                rows: rows
            ))
        }
        return ProfessionalReportDocument(
            title: "Balance Sheet",
            subtitle: "Opening, movement and closing balances",
            periodText: periodText(interval),
            generatedAt: Date(),
            tables: tables,
            notes: screenMatchedNotes
        )
    }

    private static func scopedOverview(
        type: ProfessionalReportType,
        interval: DateInterval,
        transactions: [LedgerTransaction],
        accounts: [LedgerAccount],
        store: LedgerStore
    ) -> ProfessionalReportTable? {
        func income(_ currency: String) -> Decimal {
            transactions.filter {
                store.isReportIncome($0) && store.account(withID: store.reportIncomeAccountID($0))?.currencyCode.uppercased() == currency
            }.reduce(0) { $0 + store.reportIncomeAmount($1) }
        }
        func expense(_ currency: String) -> Decimal {
            transactions.filter {
                $0.type == .expense && store.account(withID: $0.accountID)?.currencyCode.uppercased() == currency
            }.reduce(0) { $0 + $1.amount }
        }
        func transfer(_ currency: String) -> Decimal {
            transactions.filter {
                $0.type == .transfer && store.account(withID: $0.accountID)?.currencyCode.uppercased() == currency
            }.reduce(0) { $0 + $1.amount }
        }
        func balance(_ currency: String) -> (Decimal, Decimal, Decimal) {
            var assets: Decimal = 0
            var liabilities: Decimal = 0
            for account in accounts where account.currencyCode.uppercased() == currency {
                let closing = store.combinedBalance(for: [account], before: interval.end)
                if balanceSection(account: account, closing: closing).isLiability { liabilities += decimalAbs(closing) }
                else { assets += decimalAbs(closing) }
            }
            return (assets, liabilities, assets - liabilities)
        }

        var metrics: [(String, Decimal, Decimal)] = []
        switch type {
        case .financialSummary, .incomeStatement:
            let qi = income("QAR"), pi = income("PKR"), qe = expense("QAR"), pe = expense("PKR")
            metrics = [("Income", qi, pi), ("Expenses", qe, pe), ("Net Result", qi - qe, pi - pe)]
        case .incomeTransactions:
            metrics = [("Total Income", income("QAR"), income("PKR"))]
        case .expenseTransactions, .categorySummary:
            metrics = [("Total Expenses", expense("QAR"), expense("PKR"))]
        case .transfers:
            metrics = [("Transfers", transfer("QAR"), transfer("PKR"))]
        case .balanceSheet:
            let q = balance("QAR"), p = balance("PKR")
            metrics = [("Total Assets", q.0, p.0), ("Total Liabilities", q.1, p.1), ("Net Equity", q.2, p.2)]
        default:
            return nil
        }
        guard metrics.contains(where: { $0.1 != 0 || $0.2 != 0 }) else { return nil }
        return ProfessionalReportTable(
            title: "QAR & PKR Overview",
            subtitle: "PKR converted at the fixed rate: PKR 77 = QAR 1",
            columns: ["Metric", "QAR", "PKR", "PKR in QAR", "Consolidated QAR"],
            rows: metrics.map { item in
                let converted = item.2 / pkrPerQAR
                return ProfessionalReportRow([
                    .text(item.0), .number(item.1), .number(item.2), .number(converted), .number(item.1 + converted)
                ], emphasis: item.0.contains("Net") ? .total : .subtotal)
            }
        )
    }

    private static let screenMatchedNotes = [
        "This export uses the same period, accounts, currency and transaction filters shown on screen.",
        "PKR consolidated values use the fixed app rate PKR 77 = QAR 1."
    ]

'''
replace_once(service, "    private static let pkrPerQAR = Decimal(77)\n", scoped_helpers + "    private static let pkrPerQAR = Decimal(77)\n")

# Put balance-sheet section text in the wider Account column.
replace_once(
    service,
    '''                rows.append(ProfessionalReportRow([
                    .text(section.rawValue), .text(""), .text(""), .text(""), .text("")
                ], emphasis: .section))
''',
    '''                rows.append(ProfessionalReportRow([
                    .text(""), .text(section.rawValue), .text(""), .text(""), .text("")
                ], emphasis: .section))
''',
)

# Replace the PDF renderer with the approved Sample C design.
text = read(service)
start = text.index("    private static func exportPDF(_ document: ProfessionalReportDocument) throws -> URL {")
end = text.index("    private static func exportExcel(_ document: ProfessionalReportDocument) throws -> URL {", start)
new_pdf = r'''    private static func exportPDF(_ document: ProfessionalReportDocument) throws -> URL {
        let url = reportURL(document: document, extension: "pdf")
        let visibleTables = document.tables.filter(shouldIncludeTable)
        let isWide = visibleTables.contains { $0.columns.count >= 7 }
        let pageRect = isWide
            ? CGRect(x: 0, y: 0, width: 841.8, height: 595.2)
            : CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Next Ledger",
            kCGPDFContextAuthor as String: "Next Solution – Zeeshan Barvi",
            kCGPDFContextTitle as String: document.title
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let data = renderer.pdfData { context in
            let margin: CGFloat = 30
            let contentWidth = pageRect.width - margin * 2
            let green = UIColor(red: 0.125, green: 0.353, blue: 0.278, alpha: 1)
            let darkGreen = UIColor(red: 0.075, green: 0.235, blue: 0.180, alpha: 1)
            let lightGreen = UIColor(red: 0.925, green: 0.965, blue: 0.945, alpha: 1)
            let grid = UIColor(white: 0.84, alpha: 1)
            var pageNumber = 0
            var cursorY: CGFloat = 0

            func paragraphStyle(_ alignment: NSTextAlignment, lineBreak: NSLineBreakMode = .byWordWrapping) -> NSMutableParagraphStyle {
                let style = NSMutableParagraphStyle()
                style.alignment = alignment
                style.lineBreakMode = lineBreak
                style.lineSpacing = 0.8
                return style
            }

            func textHeight(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
                guard width > 2 else { return font.lineHeight }
                let rect = (text as NSString).boundingRect(
                    with: CGSize(width: width, height: 10_000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: font, .paragraphStyle: paragraphStyle(.left)],
                    context: nil
                )
                return ceil(rect.height)
            }

            func drawText(
                _ text: String,
                rect: CGRect,
                font: UIFont,
                color: UIColor,
                alignment: NSTextAlignment = .left
            ) {
                (text as NSString).draw(
                    with: rect,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [
                        .font: font,
                        .foregroundColor: color,
                        .paragraphStyle: paragraphStyle(alignment)
                    ],
                    context: nil
                )
            }

            func cellString(_ cell: ProfessionalReportCell) -> String {
                switch cell {
                case .text(let value): return value
                case .number(let value):
                    return ReportNumberFormatters.decimal.string(from: NSDecimalNumber(decimal: value)) ?? "0.00"
                }
            }

            func drawFooter() {
                let lineY = pageRect.height - 24
                grid.setFill()
                UIBezierPath(rect: CGRect(x: margin, y: lineY - 5, width: contentWidth, height: 0.5)).fill()
                drawText(
                    "Next Ledger • \(document.title) • Generated \(ReportDateFormatters.timestamp.string(from: document.generatedAt))",
                    rect: CGRect(x: margin, y: lineY, width: contentWidth - 70, height: 14),
                    font: .systemFont(ofSize: 7.2),
                    color: UIColor(white: 0.40, alpha: 1)
                )
                drawText(
                    "Page \(pageNumber)",
                    rect: CGRect(x: pageRect.width - margin - 65, y: lineY, width: 65, height: 14),
                    font: .systemFont(ofSize: 7.2, weight: .semibold),
                    color: UIColor(white: 0.40, alpha: 1),
                    alignment: .right
                )
            }

            func beginPage() {
                context.beginPage()
                pageNumber += 1
                green.setFill()
                UIBezierPath(rect: CGRect(x: 0, y: 0, width: pageRect.width, height: 58)).fill()
                drawText("NEXT LEDGER", rect: CGRect(x: margin, y: 10, width: 160, height: 14), font: .systemFont(ofSize: 8.5, weight: .heavy), color: .white)
                drawText(document.title, rect: CGRect(x: margin, y: 23, width: contentWidth, height: 24), font: .systemFont(ofSize: 17, weight: .bold), color: .white)
                drawText(document.periodText, rect: CGRect(x: margin, y: 45, width: contentWidth, height: 12), font: .systemFont(ofSize: 7.8, weight: .medium), color: UIColor.white.withAlphaComponent(0.86))
                cursorY = 70
            }

            func ensureSpace(_ height: CGFloat) {
                if cursorY + height > pageRect.height - 34 {
                    drawFooter()
                    beginPage()
                }
            }

            func columnWidths(for table: ProfessionalReportTable) -> [CGFloat] {
                let names = table.columns.map { $0.lowercased() }
                if table.columns.count == 2 { return [contentWidth * 0.69, contentWidth * 0.31] }
                if table.columns.count == 3 { return [contentWidth * 0.50, contentWidth * 0.29, contentWidth * 0.21] }
                if table.columns.count == 5 {
                    if names.contains("code") && names.contains("account") {
                        return [contentWidth * 0.12, contentWidth * 0.34, contentWidth * 0.18, contentWidth * 0.18, contentWidth * 0.18]
                    }
                    return [contentWidth * 0.27, contentWidth * 0.16, contentWidth * 0.19, contentWidth * 0.19, contentWidth * 0.19]
                }
                if table.columns.count == 6 {
                    return [contentWidth * 0.13, contentWidth * 0.22, contentWidth * 0.22, contentWidth * 0.15, contentWidth * 0.12, contentWidth * 0.16]
                }
                if table.columns.count == 7 {
                    return [contentWidth * 0.10, contentWidth * 0.17, contentWidth * 0.17, contentWidth * 0.20, contentWidth * 0.13, contentWidth * 0.09, contentWidth * 0.14]
                }
                if table.columns.count == 8 {
                    return [contentWidth * 0.10, contentWidth * 0.15, contentWidth * 0.22, contentWidth * 0.11, contentWidth * 0.105, contentWidth * 0.105, contentWidth * 0.105, contentWidth * 0.105]
                }
                return Array(repeating: contentWidth / CGFloat(max(table.columns.count, 1)), count: max(table.columns.count, 1))
            }

            func tableHeaderHeight(_ table: ProfessionalReportTable, widths: [CGFloat]) -> CGFloat {
                let font = UIFont.systemFont(ofSize: 7.2, weight: .bold)
                let heights = table.columns.enumerated().map { index, title in
                    textHeight(title, width: widths[index] - 10, font: font)
                }
                return max(23, (heights.max() ?? 10) + 10)
            }

            func drawTableHeader(_ table: ProfessionalReportTable, widths: [CGFloat]) {
                let height = tableHeaderHeight(table, widths: widths)
                green.setFill()
                UIBezierPath(roundedRect: CGRect(x: margin, y: cursorY, width: contentWidth, height: height), cornerRadius: 4).fill()
                var x = margin
                for (index, column) in table.columns.enumerated() {
                    let width = widths[index]
                    drawText(
                        column,
                        rect: CGRect(x: x + 5, y: cursorY + 5, width: width - 10, height: height - 8),
                        font: .systemFont(ofSize: 7.2, weight: .bold),
                        color: .white,
                        alignment: index > 0 && !["account", "category", "vendor", "from account", "to account"].contains(column.lowercased()) ? .right : .left
                    )
                    x += width
                }
                cursorY += height
            }

            func rowHeight(_ row: ProfessionalReportRow, table: ProfessionalReportTable, widths: [CGFloat]) -> CGFloat {
                let font = UIFont.systemFont(ofSize: table.columns.count >= 7 ? 6.6 : 7.3, weight: row.emphasis == .normal ? .regular : .semibold)
                var height: CGFloat = 20
                for index in table.columns.indices {
                    let cell = index < row.cells.count ? row.cells[index] : .text("")
                    height = max(height, textHeight(cellString(cell), width: widths[index] - 10, font: font) + 9)
                }
                return min(max(height, 21), 52)
            }

            func drawStandardTable(_ table: ProfessionalReportTable) {
                ensureSpace(64)
                let titleFont = UIFont.systemFont(ofSize: 11.5, weight: .bold)
                let titleHeight = textHeight(table.title, width: contentWidth, font: titleFont)
                drawText(table.title, rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: titleHeight + 2), font: titleFont, color: darkGreen)
                cursorY += titleHeight + 4
                if !table.subtitle.isEmpty {
                    let subtitleFont = UIFont.systemFont(ofSize: 7.8)
                    let subtitleHeight = textHeight(table.subtitle, width: contentWidth, font: subtitleFont)
                    drawText(table.subtitle, rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: subtitleHeight + 2), font: subtitleFont, color: UIColor(white: 0.38, alpha: 1))
                    cursorY += subtitleHeight + 5
                }
                let widths = columnWidths(for: table)
                drawTableHeader(table, widths: widths)
                for (rowIndex, row) in table.rows.enumerated() {
                    let height = rowHeight(row, table: table, widths: widths)
                    if cursorY + height > pageRect.height - 34 {
                        drawFooter()
                        beginPage()
                        drawText("\(table.title) — continued", rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 18), font: .systemFont(ofSize: 10, weight: .bold), color: darkGreen)
                        cursorY += 20
                        drawTableHeader(table, widths: widths)
                    }
                    let fill: UIColor
                    switch row.emphasis {
                    case .section: fill = lightGreen
                    case .subtotal: fill = UIColor(red: 0.90, green: 0.94, blue: 0.92, alpha: 1)
                    case .total: fill = green
                    case .normal: fill = rowIndex.isMultiple(of: 2) ? .white : UIColor(white: 0.975, alpha: 1)
                    }
                    fill.setFill()
                    UIBezierPath(rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: height)).fill()
                    var x = margin
                    for index in table.columns.indices {
                        let width = widths[index]
                        let cell = index < row.cells.count ? row.cells[index] : .text("")
                        let numeric: Bool
                        if case .number = cell { numeric = true } else { numeric = false }
                        let font = UIFont.systemFont(ofSize: table.columns.count >= 7 ? 6.6 : 7.3, weight: row.emphasis == .normal ? .regular : .semibold)
                        drawText(
                            cellString(cell),
                            rect: CGRect(x: x + 5, y: cursorY + 4, width: width - 10, height: height - 7),
                            font: font,
                            color: row.emphasis == .total ? .white : UIColor(white: 0.16, alpha: 1),
                            alignment: numeric ? .right : .left
                        )
                        grid.setFill()
                        UIBezierPath(rect: CGRect(x: x + width - 0.35, y: cursorY, width: 0.35, height: height)).fill()
                        x += width
                    }
                    cursorY += height
                }
                cursorY += 10
            }

            func drawSampleCSummary(_ table: ProfessionalReportTable) {
                ensureSpace(CGFloat(76 + table.rows.count * 18))
                let heading = table.title.replacingOccurrences(of: "Consolidated ", with: "")
                drawText(heading, rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 18), font: .systemFont(ofSize: 11.5, weight: .bold), color: darkGreen)
                cursorY += 19
                drawText(table.subtitle, rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 15), font: .systemFont(ofSize: 7.5), color: UIColor(white: 0.40, alpha: 1))
                cursorY += 18

                let gap: CGFloat = 10
                let panelWidth = (contentWidth - gap) / 2
                let panelHeight = CGFloat(28 + table.rows.count * 18)
                for (panelIndex, currency) in ["QAR", "PKR"].enumerated() {
                    let x = margin + CGFloat(panelIndex) * (panelWidth + gap)
                    lightGreen.setFill()
                    UIBezierPath(roundedRect: CGRect(x: x, y: cursorY, width: panelWidth, height: panelHeight), cornerRadius: 7).fill()
                    drawText(currency, rect: CGRect(x: x + 10, y: cursorY + 8, width: panelWidth - 20, height: 16), font: .systemFont(ofSize: 10.5, weight: .bold), color: darkGreen)
                    for (rowIndex, row) in table.rows.enumerated() {
                        let label = row.cells.indices.contains(0) ? cellString(row.cells[0]) : ""
                        let valueIndex = currency == "QAR" ? 1 : 2
                        let value = row.cells.indices.contains(valueIndex) ? cellString(row.cells[valueIndex]) : "0.00"
                        let y = cursorY + 27 + CGFloat(rowIndex * 18)
                        drawText(label, rect: CGRect(x: x + 10, y: y, width: panelWidth * 0.55, height: 15), font: .systemFont(ofSize: 7.2), color: UIColor(white: 0.30, alpha: 1))
                        drawText(value, rect: CGRect(x: x + panelWidth * 0.55, y: y, width: panelWidth * 0.45 - 10, height: 15), font: .systemFont(ofSize: 7.4, weight: .semibold), color: darkGreen, alignment: .right)
                    }
                }
                cursorY += panelHeight + 8
                if let last = table.rows.last {
                    let label = last.cells.indices.contains(0) ? cellString(last.cells[0]) : "Consolidated Total"
                    let value = last.cells.indices.contains(4) ? cellString(last.cells[4]) : "0.00"
                    UIColor(red: 0.86, green: 0.94, blue: 0.90, alpha: 1).setFill()
                    UIBezierPath(roundedRect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 32), cornerRadius: 7).fill()
                    drawText("Consolidated QAR — \(label)", rect: CGRect(x: margin + 10, y: cursorY + 9, width: contentWidth * 0.58, height: 16), font: .systemFont(ofSize: 8, weight: .semibold), color: darkGreen)
                    drawText("QAR \(value)", rect: CGRect(x: margin + contentWidth * 0.58, y: cursorY + 7, width: contentWidth * 0.42 - 10, height: 18), font: .systemFont(ofSize: 12, weight: .bold), color: darkGreen, alignment: .right)
                    cursorY += 42
                }
            }

            beginPage()
            if !document.subtitle.isEmpty {
                let subtitleFont = UIFont.systemFont(ofSize: 9, weight: .medium)
                let subtitleHeight = textHeight(document.subtitle, width: contentWidth, font: subtitleFont)
                drawText(document.subtitle, rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: subtitleHeight + 2), font: subtitleFont, color: UIColor(white: 0.25, alpha: 1))
                cursorY += subtitleHeight + 10
            }

            for table in visibleTables {
                if table.title.contains("QAR & PKR") && table.columns.count == 5 {
                    drawSampleCSummary(table)
                } else {
                    drawStandardTable(table)
                }
            }

            let conciseNotes = Array(document.notes.prefix(2))
            if !conciseNotes.isEmpty {
                ensureSpace(CGFloat(28 + conciseNotes.count * 22))
                drawText("Report Notes", rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 18), font: .systemFont(ofSize: 10.5, weight: .bold), color: darkGreen)
                cursorY += 20
                for note in conciseNotes {
                    let font = UIFont.systemFont(ofSize: 7.4)
                    let height = textHeight("• \(note)", width: contentWidth - 8, font: font)
                    drawText("• \(note)", rect: CGRect(x: margin + 4, y: cursorY, width: contentWidth - 8, height: height + 2), font: font, color: UIColor(white: 0.36, alpha: 1))
                    cursorY += height + 6
                }
            }
            drawFooter()
        }
        try data.write(to: url, options: .atomic)
        return url
    }

'''
text = text[:start] + new_pdf + text[end:]
write(service, text)

# Filter redundant and empty tables in Excel, and use the Sample C green palette.
replace_once(
    service,
    '''        let tables = document.tables.isEmpty
            ? [ProfessionalReportTable(title: document.title, subtitle: document.subtitle, columns: ["Status"], rows: [ProfessionalReportRow([.text("No data")])])]
            : document.tables
''',
    '''        let filteredTables = document.tables.filter(shouldIncludeTable)
        let tables = filteredTables.isEmpty
            ? [ProfessionalReportTable(title: document.title, subtitle: document.subtitle, columns: ["Status"], rows: [ProfessionalReportRow([.text("No data")])])]
            : filteredTables
''',
)

# Add the shared table visibility helper before the PDF exporter.
replace_once(
    service,
    '''    private static func exportPDF(_ document: ProfessionalReportDocument) throws -> URL {
''',
    '''    private static func shouldIncludeTable(_ table: ProfessionalReportTable) -> Bool {
        if table.title.hasPrefix("Financial Summary —") || table.title.hasPrefix("Balance Sheet Summary —") {
            return false
        }
        let blocked = ["no account balances", "no transactions", "no reviewed", "no data"]
        var meaningfulText = false
        var nonZeroNumber = false
        for row in table.rows {
            for cell in row.cells {
                switch cell {
                case .number(let value):
                    if value != 0 { nonZeroNumber = true }
                case .text(let value):
                    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if !clean.isEmpty && !blocked.contains(where: { clean.contains($0) }) {
                        meaningfulText = true
                    }
                }
            }
        }
        return nonZeroNumber || (meaningfulText && !table.rows.isEmpty)
    }

    private static func exportPDF(_ document: ProfessionalReportDocument) throws -> URL {
''',
)

text = read(service)
text = text.replace("FF3A1E7A", "FF205A47")
text = text.replace("FFEFEAF8", "FFE8F3EE")
text = text.replace("FF21163E", "FF183D31")
text = text.replace('applyAlignment="1"><alignment vertical="center"/></xf>', 'applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>', 1)
write(service, text)

# Replace the quick-download view so it carries the active report scope.
write(button, r'''import SwiftUI
import UIKit

struct ReportDownloadButton: View {
    @EnvironmentObject private var store: LedgerStore

    let type: ProfessionalReportType
    let startDate: Date
    let endDate: Date
    var transactionIDs: [UUID] = []
    var accountIDs: [UUID] = []
    var currencyCode: String? = nil
    var reportTitle: String? = nil

    @State private var isGenerating = false
    @State private var shareFile: QuickReportShareFile?
    @State private var errorMessage: String?

    var body: some View {
        Menu {
            Button { generate(.pdf) } label: {
                Label("PDF", systemImage: "doc.richtext.fill")
            }
            Button { generate(.excel) } label: {
                Label("Excel", systemImage: "tablecells.fill")
            }
        } label: {
            Group {
                if isGenerating {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppTheme.purple)
                }
            }
            .frame(width: 36, height: 36)
            .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .disabled(isGenerating)
        .accessibilityLabel("Download reviewed \(reportTitle ?? type.rawValue)")
        .sheet(item: $shareFile) { file in
            QuickReportActivityView(items: [file.url]).ignoresSafeArea()
        }
        .alert("Report Export", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "The report could not be generated.")
        }
    }

    private func generate(_ format: ProfessionalExportFormat) {
        isGenerating = true
        defer { isGenerating = false }
        let scope = ProfessionalReportScope(
            transactionIDs: Set(transactionIDs),
            accountIDs: Set(accountIDs),
            currencyCode: currencyCode,
            reportTitle: reportTitle
        )
        let document = ProfessionalReportBuilder.build(
            type: type,
            startDate: startDate,
            endDate: endDate,
            store: store,
            scope: scope
        )
        do {
            shareFile = QuickReportShareFile(url: try ProfessionalReportExporter.export(document, format: format))
        } catch {
            errorMessage = "The \(format.rawValue) report could not be generated. \(error.localizedDescription)"
        }
    }
}

struct ProfessionalReportTypeView: View {
    let type: ProfessionalReportType

    @AppStorage("ProfessionalReportStartDateV1") private var storedStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
    @AppStorage("ProfessionalReportEndDateV1") private var storedEndDate = Date().timeIntervalSince1970

    private var startDate: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: storedStartDate) },
            set: { value in
                storedStartDate = Calendar.current.startOfDay(for: value).timeIntervalSince1970
                if storedStartDate > storedEndDate { storedEndDate = storedStartDate }
            }
        )
    }

    private var endDate: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: storedEndDate) },
            set: { value in
                storedEndDate = Calendar.current.startOfDay(for: value).timeIntervalSince1970
                if storedEndDate < storedStartDate { storedStartDate = storedEndDate }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: type.icon)
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.purple)
                        .frame(width: 48, height: 48)
                        .background(AppTheme.purple.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(type.rawValue).font(.headline)
                        Text(type.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 5)
            }

            Section(type.usesAsOfDateOnly ? "Report Date" : "Period") {
                if type.usesAsOfDateOnly {
                    DatePicker("As of", selection: endDate, displayedComponents: .date)
                } else {
                    DatePicker("From", selection: startDate, displayedComponents: .date)
                    DatePicker("To", selection: endDate, in: startDate.wrappedValue..., displayedComponents: .date)
                }
            }

            Section {
                Label("Review the dates, then tap the download button above.", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(type.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ReportDownloadButton(type: type, startDate: startDate.wrappedValue, endDate: endDate.wrappedValue)
            }
        }
    }
}

private struct QuickReportShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct QuickReportActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
''')

# Remove premature download buttons from the report list; keep export inside reviewed screens.
replace_once(
    reports,
    '''                    ForEach(filteredReportKinds) { kind in
                        HStack(spacing: 8) {
                            NavigationLink {
                                ReportDetailView(kind: kind)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(kind.rawValue).font(.headline)
                                        Text(kind.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: kind.icon)
                                        .foregroundStyle(AppTheme.purple)
                                }
                                .padding(.vertical, 5)
                            }
                            ReportDownloadButton(
                                type: kind.exportType,
                                startDate: quickReportInterval.start,
                                endDate: quickReportEndDate
                            )
                        }
                    }
''',
    '''                    ForEach(filteredReportKinds) { kind in
                        NavigationLink {
                            ReportDetailView(kind: kind)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(kind.rawValue).font(.headline)
                                    Text(kind.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: kind.icon)
                                    .foregroundStyle(AppTheme.purple)
                            }
                            .padding(.vertical, 5)
                        }
                    }
''',
)

replace_once(
    reports,
    '''                    ForEach([
                        ProfessionalReportType.incomeStatement,
                        .balanceSheet,
                        .payablesAging,
                        .payablesSummary,
                        .receivablesAging,
                        .receivablesSummary
                    ]) { type in
                        HStack(spacing: 8) {
                            NavigationLink {
                                ProfessionalReportTypeView(type: type)
                            } label: {
                                Label(type.rawValue, systemImage: type.icon)
                            }
                            ReportDownloadButton(
                                type: type,
                                startDate: Date(timeIntervalSince1970: professionalStart),
                                endDate: Date(timeIntervalSince1970: professionalEnd)
                            )
                        }
                    }
''',
    '''                    ForEach([
                        ProfessionalReportType.incomeStatement,
                        .balanceSheet,
                        .payablesAging,
                        .payablesSummary,
                        .receivablesAging,
                        .receivablesSummary
                    ]) { type in
                        NavigationLink {
                            ProfessionalReportTypeView(type: type)
                        } label: {
                            Label(type.rawValue, systemImage: type.icon)
                        }
                    }
''',
)

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
                        transactionIDs: selectedTransactions.map(\\.id),
                        currencyCode: store.currencyCode,
                        reportTitle: kind.rawValue
                    )
''',
)

# Add a screen-matched export to Custom Account Report.
replace_once(
    reports,
    '''        .navigationTitle("Custom Account Report")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
''',
    '''        .navigationTitle("Custom Account Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ReportDownloadButton(
                    type: .financialSummary,
                    startDate: interval.start,
                    endDate: Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end,
                    transactionIDs: exportTransactionIDs,
                    accountIDs: Array(selected),
                    reportTitle: "Custom Account Report"
                )
            }
        }
        .onAppear {
''',
)

replace_once(
    reports,
    '''    private var interval: DateInterval {
        DateInterval(start: Calendar.current.startOfDay(for: start),
''',
    '''    private var exportTransactionIDs: [UUID] {
        Array(Set(
            matchingTransactions(.income, in: interval).map(\\.id) +
            matchingTransactions(.expense, in: interval).map(\\.id)
        ))
    }

    private var interval: DateInterval {
        DateInterval(start: Calendar.current.startOfDay(for: start),
''',
)

# Add screen-matched export to Loan Movement after its date selection.
replace_once(
    reports,
    '''        .navigationTitle("Loan Movement")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var interval: DateInterval {
''',
    '''        .navigationTitle("Loan Movement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ReportDownloadButton(
                    type: .transfers,
                    startDate: interval.start,
                    endDate: Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end,
                    transactionIDs: exportTransactionIDs,
                    accountIDs: loanAccounts.map(\\.id),
                    reportTitle: "Loan Movement"
                )
            }
        }
    }

    private var exportTransactionIDs: [UUID] {
        store.transactions.filter { transaction in
            guard interval.contains(transaction.date) else { return false }
            let source = transaction.accountID ?? LedgerAccount.legacyMainID
            let destination = transaction.destinationAccountID ?? LedgerAccount.legacyMainID
            let ids = Set(loanAccounts.map(\\.id))
            return ids.contains(source) || ids.contains(destination)
        }.map(\\.id)
    }

    private var interval: DateInterval {
''',
)

print("Applied Sample C, screen-matched exports, wrapped text, and reviewed-report download controls.")
