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
        raise RuntimeError(f"Expected one match in {relative}, found {count}: {old[:240]!r}")
    write(relative, text.replace(old, new, 1))


service = "DailyLedger/Services/ProfessionalReportExportService.swift"

replace_once(
    service,
    '''enum ProfessionalReportType: String, CaseIterable, Identifiable {
    case financialSummary = "Financial Summary"
    case incomeStatement = "Income Statement"
''',
    '''enum ProfessionalReportType: String, CaseIterable, Identifiable {
    case financialSummary = "Financial Summary"
    case incomeTransactions = "Income Report"
    case expenseTransactions = "Expense Report"
    case transfers = "Loans / Transfers"
    case categorySummary = "Category Report"
    case incomeStatement = "Income Statement"
''',
)

replace_once(
    service,
    '''        case .financialSummary:
            return "Income, expenses and net result by currency"
        case .incomeStatement:
''',
    '''        case .financialSummary:
            return "Income, expenses and net result with one QAR total"
        case .incomeTransactions:
            return "Detailed income transactions with native and QAR amounts"
        case .expenseTransactions:
            return "Detailed expenses with native and QAR amounts"
        case .transfers:
            return "Account and loan transfers for the selected period"
        case .categorySummary:
            return "Expense totals by category with one QAR total"
        case .incomeStatement:
''',
)

replace_once(
    service,
    '''        case .financialSummary: return "chart.bar.doc.horizontal.fill"
        case .incomeStatement: return "chart.line.uptrend.xyaxis"
''',
    '''        case .financialSummary: return "chart.bar.doc.horizontal.fill"
        case .incomeTransactions: return "arrow.down.left.circle.fill"
        case .expenseTransactions: return "arrow.up.right.circle.fill"
        case .transfers: return "arrow.left.arrow.right.circle.fill"
        case .categorySummary: return "square.grid.2x2.fill"
        case .incomeStatement: return "chart.line.uptrend.xyaxis"
''',
)

old_build = '''        switch type {
        case .financialSummary:
            return financialSummary(interval: interval, store: store)
        case .incomeStatement:
            return incomeStatement(interval: interval, store: store)
        case .balanceSheet:
            return balanceSheet(interval: interval, store: store)
        case .payablesAging:
            return agingReport(isPayable: true, detailed: true, asOf: endDay, store: store)
        case .payablesSummary:
            return agingReport(isPayable: true, detailed: false, asOf: endDay, store: store)
        case .receivablesAging:
            return agingReport(isPayable: false, detailed: true, asOf: endDay, store: store)
        case .receivablesSummary:
            return agingReport(isPayable: false, detailed: false, asOf: endDay, store: store)
        }
'''
new_build = '''        let document: ProfessionalReportDocument
        switch type {
        case .financialSummary:
            document = financialSummary(interval: interval, store: store)
        case .incomeTransactions:
            document = transactionReport(isIncome: true, interval: interval, store: store)
        case .expenseTransactions:
            document = transactionReport(isIncome: false, interval: interval, store: store)
        case .transfers:
            document = transferReport(interval: interval, store: store)
        case .categorySummary:
            document = categoryReport(interval: interval, store: store)
        case .incomeStatement:
            document = incomeStatement(interval: interval, store: store)
        case .balanceSheet:
            document = balanceSheet(interval: interval, store: store)
        case .payablesAging:
            document = agingReport(isPayable: true, detailed: true, asOf: endDay, store: store)
        case .payablesSummary:
            document = agingReport(isPayable: true, detailed: false, asOf: endDay, store: store)
        case .receivablesAging:
            document = agingReport(isPayable: false, detailed: true, asOf: endDay, store: store)
        case .receivablesSummary:
            document = agingReport(isPayable: false, detailed: false, asOf: endDay, store: store)
        }
        return addQARConsolidation(document, type: type, interval: interval, store: store)
'''
replace_once(service, old_build, new_build)

insert_before_financial = r'''    private static let pkrPerQAR = Decimal(77)

    private static func addQARConsolidation(
        _ document: ProfessionalReportDocument,
        type: ProfessionalReportType,
        interval: DateInterval,
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        guard let overview = consolidatedOverview(type: type, interval: interval, store: store) else {
            return document
        }
        return ProfessionalReportDocument(
            title: document.title,
            subtitle: document.subtitle,
            periodText: document.periodText,
            generatedAt: document.generatedAt,
            tables: [overview] + document.tables,
            notes: document.notes
        )
    }

    private static func consolidatedOverview(
        type: ProfessionalReportType,
        interval: DateInterval,
        store: LedgerStore
    ) -> ProfessionalReportTable? {
        func income(_ currency: String) -> Decimal {
            store.transactions.lazy.filter {
                interval.contains($0.date) &&
                    store.isReportIncome($0) &&
                    store.account(withID: store.reportIncomeAccountID($0))?.currencyCode.uppercased() == currency
            }.reduce(Decimal.zero) { $0 + store.reportIncomeAmount($1) }
        }

        func expenses(_ currency: String) -> Decimal {
            store.transactions.lazy.filter {
                interval.contains($0.date) && $0.type == .expense &&
                    store.account(withID: $0.accountID)?.currencyCode.uppercased() == currency
            }.reduce(Decimal.zero) { $0 + $1.amount }
        }

        func transfers(_ currency: String) -> Decimal {
            store.transactions.lazy.filter {
                interval.contains($0.date) && $0.type == .transfer &&
                    store.account(withID: $0.accountID)?.currencyCode.uppercased() == currency
            }.reduce(Decimal.zero) { $0 + $1.amount }
        }

        func balanceMetrics(_ currency: String) -> (assets: Decimal, liabilities: Decimal, equity: Decimal) {
            var assets: Decimal = 0
            var liabilities: Decimal = 0
            for account in store.activeAccounts where account.currencyCode.uppercased() == currency {
                let closing = store.combinedBalance(for: [account], before: interval.end)
                let section = balanceSection(account: account, closing: closing)
                if section.isLiability {
                    liabilities += decimalAbs(closing)
                } else {
                    assets += decimalAbs(closing)
                }
            }
            return (assets, liabilities, assets - liabilities)
        }

        func agingOutstanding(_ currency: String, payable: Bool) -> Decimal {
            store.activeAccounts.lazy.filter(isAgingAccount).filter {
                $0.currencyCode.uppercased() == currency
            }.reduce(Decimal.zero) { total, account in
                let balance = store.combinedBalance(for: [account], before: interval.end)
                if payable, balance < 0 { return total + decimalAbs(balance) }
                if !payable, balance > 0 { return total + balance }
                return total
            }
        }

        var metrics: [(String, Decimal, Decimal)] = []
        switch type {
        case .financialSummary, .incomeStatement:
            let qarIncome = income("QAR")
            let pkrIncome = income("PKR")
            let qarExpense = expenses("QAR")
            let pkrExpense = expenses("PKR")
            metrics = [
                ("Income", qarIncome, pkrIncome),
                ("Expenses", qarExpense, pkrExpense),
                ("Net Result", qarIncome - qarExpense, pkrIncome - pkrExpense)
            ]
        case .incomeTransactions:
            metrics = [("Total Income", income("QAR"), income("PKR"))]
        case .expenseTransactions, .categorySummary:
            metrics = [("Total Expenses", expenses("QAR"), expenses("PKR"))]
        case .transfers:
            metrics = [("Transfers Out", transfers("QAR"), transfers("PKR"))]
        case .balanceSheet:
            let qar = balanceMetrics("QAR")
            let pkr = balanceMetrics("PKR")
            metrics = [
                ("Total Assets", qar.assets, pkr.assets),
                ("Total Liabilities", qar.liabilities, pkr.liabilities),
                ("Net Equity / Balance", qar.equity, pkr.equity)
            ]
        case .payablesAging, .payablesSummary:
            metrics = [("Outstanding Payables", agingOutstanding("QAR", payable: true), agingOutstanding("PKR", payable: true))]
        case .receivablesAging, .receivablesSummary:
            metrics = [("Outstanding Receivables", agingOutstanding("QAR", payable: false), agingOutstanding("PKR", payable: false))]
        }

        guard metrics.contains(where: { $0.1 != 0 || $0.2 != 0 }) else { return nil }
        let rows = metrics.map { metric -> ProfessionalReportRow in
            let pkrInQAR = metric.2 / pkrPerQAR
            return ProfessionalReportRow([
                .text(metric.0),
                .number(metric.1),
                .number(metric.2),
                .number(pkrInQAR),
                .number(metric.1 + pkrInQAR)
            ], emphasis: metric.0.contains("Net") ? .total : .subtotal)
        }
        return ProfessionalReportTable(
            title: "QAR & PKR Consolidated Overview",
            subtitle: "PKR converted at the preset fixed rate: PKR 77 = QAR 1",
            columns: ["Metric", "QAR", "PKR", "PKR in QAR", "Consolidated QAR"],
            rows: rows
        )
    }

    private static func transactionReport(
        isIncome: Bool,
        interval: DateInterval,
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        let title = isIncome ? "Income Report" : "Expense Report"
        let items = store.transactions.filter { transaction in
            guard interval.contains(transaction.date) else { return false }
            return isIncome ? store.isReportIncome(transaction) : transaction.type == .expense
        }.sorted { $0.date < $1.date }

        var rows = items.map { transaction -> ProfessionalReportRow in
            let accountID = isIncome ? store.reportIncomeAccountID(transaction) : transaction.accountID
            let account = store.account(withID: accountID)
            let currency = account?.currencyCode.uppercased() ?? "QAR"
            let amount = isIncome ? store.reportIncomeAmount(transaction) : transaction.amount
            let qarEquivalent: ProfessionalReportCell = currency == "QAR"
                ? .number(amount)
                : currency == "PKR" ? .number(amount / pkrPerQAR) : .text("—")
            let vendor = transaction.vendor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return ProfessionalReportRow([
                .text(shortDate(transaction.date)),
                .text(account?.name ?? "Unassigned"),
                .text(transaction.category),
                .text(vendor.isEmpty ? "—" : vendor),
                .number(amount),
                .text(currency),
                qarEquivalent
            ])
        }
        if rows.isEmpty {
            rows = [ProfessionalReportRow([
                .text("—"), .text("No transactions"), .text("—"), .text("—"), .number(0), .text("QAR"), .number(0)
            ])]
        }
        return ProfessionalReportDocument(
            title: title,
            subtitle: isIncome ? "Income transactions" : "Expense transactions",
            periodText: periodText(interval),
            generatedAt: Date(),
            tables: [ProfessionalReportTable(
                title: title,
                subtitle: "Native amount retained; QAR equivalent shown for QAR and PKR",
                columns: ["Date", "Account", "Category", "Vendor", "Amount", "Currency", "QAR Eq."],
                rows: rows
            )],
            notes: nativeCurrencyNotes
        )
    }

    private static func transferReport(
        interval: DateInterval,
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        let items = store.transactions.filter {
            interval.contains($0.date) && $0.type == .transfer
        }.sorted { $0.date < $1.date }
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
            rows = [ProfessionalReportRow([
                .text("—"), .text("No transfers"), .text("—"), .number(0), .text("QAR"), .number(0)
            ])]
        }
        return ProfessionalReportDocument(
            title: "Loans / Transfers",
            subtitle: "Account and loan movements",
            periodText: periodText(interval),
            generatedAt: Date(),
            tables: [ProfessionalReportTable(
                title: "Transfer Detail",
                subtitle: "Source currency retained with QAR equivalent",
                columns: ["Date", "From", "To", "Amount", "Currency", "QAR Eq."],
                rows: rows
            )],
            notes: nativeCurrencyNotes
        )
    }

    private static func categoryReport(
        interval: DateInterval,
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        var totals: [String: (qar: Decimal, pkr: Decimal)] = [:]
        for transaction in store.transactions where interval.contains(transaction.date) && transaction.type == .expense {
            let currency = store.account(withID: transaction.accountID)?.currencyCode.uppercased() ?? "QAR"
            var value = totals[transaction.category] ?? (0, 0)
            if currency == "PKR" { value.pkr += transaction.amount }
            else if currency == "QAR" { value.qar += transaction.amount }
            totals[transaction.category] = value
        }
        var rows = totals.keys.sorted(by: localizedSort).map { category -> ProfessionalReportRow in
            let value = totals[category] ?? (0, 0)
            let pkrInQAR = value.pkr / pkrPerQAR
            return ProfessionalReportRow([
                .text(category), .number(value.qar), .number(value.pkr), .number(pkrInQAR), .number(value.qar + pkrInQAR)
            ])
        }
        if rows.isEmpty {
            rows = [ProfessionalReportRow([.text("No expenses"), .number(0), .number(0), .number(0), .number(0)])]
        }
        return ProfessionalReportDocument(
            title: "Category Report",
            subtitle: "Expense categories in QAR and PKR",
            periodText: periodText(interval),
            generatedAt: Date(),
            tables: [ProfessionalReportTable(
                title: "Expense Categories",
                subtitle: "One readable table with native and consolidated QAR amounts",
                columns: ["Category", "QAR", "PKR", "PKR in QAR", "Consolidated QAR"],
                rows: rows
            )],
            notes: nativeCurrencyNotes
        )
    }

'''
replace_once(service, "    private static func financialSummary(\n", insert_before_financial + "    private static func financialSummary(\n")

replace_once(
    service,
    '''    private static let nativeCurrencyNotes = [
        "Each currency is presented separately in its native amount.",
        "The export does not force an exchange-rate conversion between QAR, PKR, USD or other currencies."
    ]
''',
    '''    private static let nativeCurrencyNotes = [
        "QAR and PKR are shown together. Consolidated totals use the preset fixed rate PKR 77 = QAR 1.",
        "Native QAR and PKR amounts remain visible for checking and reconciliation.",
        "Currencies other than QAR and PKR remain in their native amount without forced conversion."
    ]
''',
)

# Compact, readable PDF spacing rather than oversized blocks.
for old, new in [
    ("let margin: CGFloat = 34", "let margin: CGFloat = 28"),
    ("height: 78)", "height: 64)"),
    ("y: 15, width: 180, height: 18", "y: 11, width: 180, height: 16"),
    ("y: 31, width: contentWidth, height: 26", "y: 25, width: contentWidth, height: 22"),
    ("ofSize: 20, weight: .bold", "ofSize: 17, weight: .bold"),
    ("y: 58, width: contentWidth, height: 14", "y: 47, width: contentWidth, height: 13"),
    ("cursorY = 94", "cursorY = 76"),
    ("let height: CGFloat = 27", "let height: CGFloat = 23"),
    ("cursorY + rowHeight > pageRect.height - 42", "cursorY + rowHeight > pageRect.height - 38"),
    ("let rowHeight: CGFloat = table.columns.count >= 8 ? 31 : 25", "let rowHeight: CGFloat = table.columns.count >= 8 ? 27 : 22"),
    ("cursorY += 16\n            }", "cursorY += 9\n            }")
]:
    text = read(service)
    if old in text:
        write(service, text.replace(old, new, 1))

reports = "DailyLedger/Views/ReportsView.swift"
replace_once(
    reports,
    '''    var icon: String {
        switch self {
        case .summary: return "chart.bar.xaxis"
        case .income: return "arrow.down.left.circle.fill"
        case .expenses: return "arrow.up.right.circle.fill"
        case .loans: return "arrow.left.arrow.right.circle.fill"
        case .categories: return "square.grid.2x2.fill"
        }
    }
}
''',
    '''    var icon: String {
        switch self {
        case .summary: return "chart.bar.xaxis"
        case .income: return "arrow.down.left.circle.fill"
        case .expenses: return "arrow.up.right.circle.fill"
        case .loans: return "arrow.left.arrow.right.circle.fill"
        case .categories: return "square.grid.2x2.fill"
        }
    }

    var exportType: ProfessionalReportType {
        switch self {
        case .summary: return .financialSummary
        case .income: return .incomeTransactions
        case .expenses: return .expenseTransactions
        case .loans: return .transfers
        case .categories: return .categorySummary
        }
    }
}
''',
)

replace_once(
    reports,
    '''struct ReportsView: View {
    @State private var searchText = ""
''',
    '''struct ReportsView: View {
    @State private var searchText = ""
    @AppStorage("ReportPeriodSelection") private var storedPeriod = ReportPeriod.month.rawValue
    @AppStorage("ReportCustomStart") private var storedCustomStart = Date().timeIntervalSince1970
    @AppStorage("ReportCustomEnd") private var storedCustomEnd = Date().timeIntervalSince1970
    @AppStorage("ProfessionalReportStartDateV1") private var professionalStart = Calendar.current.date(byAdding: .month, value: -1, to: Date())?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
    @AppStorage("ProfessionalReportEndDateV1") private var professionalEnd = Date().timeIntervalSince1970
''',
)

old_rows = '''                    ForEach(filteredReportKinds) { kind in
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
'''
new_rows = '''                    ForEach(filteredReportKinds) { kind in
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
'''
replace_once(reports, old_rows, new_rows)

replace_once(
    reports,
    '''                } header: {
                    Text("Choose a report")
                } footer: {
                    Text("Select a report first, then choose its month or year.")
                }
''',
    '''                } header: {
                    Text("Choose a report")
                } footer: {
                    Text("Open a report or tap its download icon for PDF or Excel.")
                }

                Section("Statements & Aging") {
                    ForEach([
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
                }
''',
)

replace_once(
    reports,
    '''    private var filteredReportKinds: [ReportKind] {
''',
    '''    private var quickReportInterval: DateInterval {
        let period = ReportPeriod(rawValue: storedPeriod) ?? .month
        if period == .custom {
            let start = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: storedCustomStart))
            let end = Calendar.current.date(
                byAdding: .day,
                value: 1,
                to: Calendar.current.startOfDay(for: Date(timeIntervalSince1970: storedCustomEnd))
            ) ?? Date()
            return DateInterval(start: start, end: end)
        }
        let component: Calendar.Component
        switch period {
        case .day: component = .day
        case .year: component = .year
        default: component = .month
        }
        return Calendar.current.dateInterval(of: component, for: Date()) ?? DateInterval(start: Date(), duration: 1)
    }

    private var quickReportEndDate: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: quickReportInterval.end) ?? quickReportInterval.end
    }

    private var filteredReportKinds: [ReportKind] {
''',
)

replace_once(
    reports,
    '''            .toolbar {
                if kind == .summary {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            editingSummaryCard = FinanceSummaryCustomCard(
                                currencyCode: store.currencyCode
                            )
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .accessibilityLabel("Add custom account balance card")
                    }
                }
            }
''',
    '''            .toolbar {
                if kind == .summary {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            editingSummaryCard = FinanceSummaryCustomCard(
                                currencyCode: store.currencyCode
                            )
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .accessibilityLabel("Add custom account balance card")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ReportDownloadButton(
                        type: kind.exportType,
                        startDate: selectedInterval.start,
                        endDate: reportExportEndDate
                    )
                }
            }
''',
)

replace_once(
    reports,
    '''    private var transactionList: some View {
''',
    '''    private var reportExportEndDate: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: selectedInterval.end) ?? selectedInterval.end
    }

    private var transactionList: some View {
''',
)

print("Added per-report PDF/Excel downloads, QAR/PKR consolidation and compact report formatting.")
