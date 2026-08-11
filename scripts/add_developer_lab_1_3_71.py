from pathlib import Path


def must_replace(text: str, old: str, new: str, label: str, count: int = 1) -> str:
    actual = text.count(old)
    if actual < count:
        raise SystemExit(f"{label}: expected at least {count} occurrence(s), found {actual}")
    return text.replace(old, new, count)


def replace_between(text: str, start: str, end: str, replacement: str, label: str) -> str:
    a = text.find(start)
    if a < 0:
        raise SystemExit(f"{label}: start marker not found")
    b = text.find(end, a + len(start))
    if b < 0:
        raise SystemExit(f"{label}: end marker not found")
    return text[:a] + replacement + text[b:]


# Version/build.
project = Path("project.yml")
text = project.read_text()
text = must_replace(text, 'MARKETING_VERSION: "1.3.70"', 'MARKETING_VERSION: "1.3.71"', "project version")
text = must_replace(text, 'CURRENT_PROJECT_VERSION: "78"', 'CURRENT_PROJECT_VERSION: "79"', "project build")
project.write_text(text)

# Settings entry + visible version.
settings = Path("DailyLedger/Views/SettingsView.swift")
text = settings.read_text()
about_anchor = '''                Section {
                    NavigationLink {
                        SettingsSectionPage(title: "About") {
'''
developer_section = '''                Section {
                    NavigationLink {
                        DeveloperLabView()
                    } label: {
                        Label("Developer Lab", systemImage: "hammer.fill")
                            .foregroundStyle(AppTheme.orange)
                    }
                } footer: {
                    Text("Advanced live customization for reports, charts, dashboard, transaction rows, and 2D / 3D appearance. Disable its master switch any time to restore normal app behavior.")
                }

'''
text = must_replace(text, about_anchor, developer_section + about_anchor, "settings developer section")
text = must_replace(text, 'LabeledContent("Version", value: "1.3.70")', 'LabeledContent("Version", value: "1.3.71")', "settings version")
settings.write_text(text)

# Reports home and report-detail customizations.
reports = Path("DailyLedger/Views/ReportsView.swift")
text = reports.read_text()

reports_props_anchor = '''    @AppStorage("ProfessionalReportEndDateV1") private var professionalEnd = Date().timeIntervalSince1970

    var body: some View {
'''
reports_props = '''    @AppStorage("ProfessionalReportEndDateV1") private var professionalEnd = Date().timeIntervalSince1970
    @AppStorage(DeveloperLabKey.enabled) private var devEnabled = true
    @AppStorage(DeveloperLabKey.showReportsRegisters) private var devShowRegisters = true
    @AppStorage(DeveloperLabKey.showReportsPlanning) private var devShowPlanning = true
    @AppStorage(DeveloperLabKey.showReportsCore) private var devShowCore = true
    @AppStorage(DeveloperLabKey.showReportsStatements) private var devShowStatements = true

    var body: some View {
'''
text = must_replace(text, reports_props_anchor, reports_props, "reports home props")

text = must_replace(
    text,
    '''            List {
                Section("Accounting Registers") {''',
    '''            List {
                if !devEnabled || devShowRegisters {
                Section("Accounting Registers") {''',
    "reports registers open",
)
text = must_replace(
    text,
    '''                }
                Section("Planning & Comparison") {''',
    '''                }
                }
                if !devEnabled || devShowPlanning {
                Section("Planning & Comparison") {''',
    "reports planning boundary",
)
text = must_replace(
    text,
    '''                }
                Section {
                    ForEach(filteredReportKinds) { kind in''',
    '''                }
                }
                if !devEnabled || devShowCore {
                Section {
                    ForEach(filteredReportKinds) { kind in''',
    "reports core boundary",
)
text = must_replace(
    text,
    '''                } footer: {
                    Text("Open a report or tap its download icon for PDF or Excel.")
                }

                Section("Statements & Aging") {''',
    '''                } footer: {
                    Text("Open a report or tap its download icon for PDF or Excel.")
                }
                }

                if !devEnabled || devShowStatements {
                Section("Statements & Aging") {''',
    "reports statements boundary",
)
text = must_replace(
    text,
    '''                }
            }
            .listStyle(.insetGrouped)''',
    '''                }
                }
            }
            .listStyle(.insetGrouped)''',
    "reports statements close",
)

report_detail_anchor = '''    @State private var editingSummaryCard: FinanceSummaryCustomCard?
    @State private var editingClosingBalance = false

    var body: some View {
'''
report_detail_props = '''    @State private var editingSummaryCard: FinanceSummaryCustomCard?
    @State private var editingClosingBalance = false
    @AppStorage(DeveloperLabKey.enabled) private var devEnabled = true
    @AppStorage(DeveloperLabKey.density) private var devDensity = DeveloperDensity.standard.rawValue
    @AppStorage(DeveloperLabKey.reportBlockSpacing) private var devReportBlockSpacing = 18.0
    @AppStorage(DeveloperLabKey.reportPagePadding) private var devReportPagePadding = 16.0
    @AppStorage(DeveloperLabKey.showReportPeriodPicker) private var devShowPeriodPicker = true
    @AppStorage(DeveloperLabKey.showReportPeriodNavigator) private var devShowPeriodNavigator = true
    @AppStorage(DeveloperLabKey.showReportActivityChart) private var devShowActivityChart = true
    @AppStorage(DeveloperLabKey.showReportCategoryBreakdown) private var devShowCategoryBreakdown = true
    @AppStorage(DeveloperLabKey.showReportTransactionList) private var devShowTransactionList = true
    @AppStorage(DeveloperLabKey.showReportDownload) private var devShowReportDownload = true
    @AppStorage(DeveloperLabKey.showReportFooterTotal) private var devShowFooterTotal = true
    @AppStorage(DeveloperLabKey.showReportTransactionCount) private var devShowTransactionCount = true
    @AppStorage(DeveloperLabKey.reportTransactionOrder) private var devTransactionOrder = DeveloperTransactionOrder.newest.rawValue
    @AppStorage(DeveloperLabKey.reportCategoryLimit) private var devCategoryLimit = 20
    @AppStorage(DeveloperLabKey.showCategoryProgress) private var devShowCategoryProgress = true
    @AppStorage(DeveloperLabKey.showSummaryNetBalance) private var devShowSummaryNet = true
    @AppStorage(DeveloperLabKey.showSummaryRateNote) private var devShowSummaryRate = true
    @AppStorage(DeveloperLabKey.showSummaryConnectors) private var devShowSummaryConnectors = true
    @AppStorage(DeveloperLabKey.showSummaryIncomeColumn) private var devShowIncomeColumn = true
    @AppStorage(DeveloperLabKey.showSummaryExpenseColumn) private var devShowExpenseColumn = true
    @AppStorage(DeveloperLabKey.showSummaryPrimaryCards) private var devShowPrimaryCards = true
    @AppStorage(DeveloperLabKey.showSummaryRefunds) private var devShowRefunds = true
    @AppStorage(DeveloperLabKey.showSummaryLoans) private var devShowLoans = true
    @AppStorage(DeveloperLabKey.showSummaryOperators) private var devShowSummaryOperators = true
    @AppStorage(DeveloperLabKey.showSummaryOpeningBalance) private var devShowOpeningBalance = true
    @AppStorage(DeveloperLabKey.showSummaryCustomBalanceCards) private var devShowCustomBalanceCards = true
    @AppStorage(DeveloperLabKey.showSummaryPKRConversion) private var devShowPKRConversion = true
    @AppStorage(DeveloperLabKey.summaryCompactCards) private var devSummaryCompactCards = true
    @AppStorage(DeveloperLabKey.summaryLoanSort) private var devSummaryLoanSort = DeveloperLoanSort.alphabetical.rawValue

    var body: some View {
'''
text = must_replace(text, report_detail_anchor, report_detail_props, "report detail props")

picker_block = '''                    Picker("Report period", selection: $storedPeriod) {
                        ForEach(ReportPeriod.allCases) { value in
                            Text(value.rawValue).tag(value.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    periodNavigator
                    if kind == .summary { totalCards }
                    if kind == .summary || kind == .income {
                        activityChart
                    }
                    if kind == .summary || kind == .categories {
                        categoryBreakdown
                    }
                    if kind == .income || kind == .expenses || kind == .loans {
                        transactionList
                    }
'''
picker_new = '''                    if !devEnabled || devShowPeriodPicker {
                        Picker("Report period", selection: $storedPeriod) {
                            ForEach(ReportPeriod.allCases) { value in
                                Text(value.rawValue).tag(value.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if !devEnabled || devShowPeriodNavigator { periodNavigator }
                    if kind == .summary { totalCards }
                    if (kind == .summary || kind == .income) && (!devEnabled || devShowActivityChart) {
                        activityChart
                    }
                    if (kind == .summary || kind == .categories) && (!devEnabled || devShowCategoryBreakdown) {
                        categoryBreakdown
                    }
                    if (kind == .income || kind == .expenses || kind == .loans) && (!devEnabled || devShowTransactionList) {
                        transactionList
                    }
'''
text = must_replace(text, picker_block, picker_new, "report detail body controls")
text = must_replace(
    text,
    '''                .padding(16)
                .padding(.bottom, 24)''',
    '''                .padding(effectiveReportPagePadding)
                .padding(.bottom, 24)''',
    "report detail padding",
)

report_download = '''                ToolbarItem(placement: .navigationBarTrailing) {
                    ReportDownloadButton(
                        type: kind.exportType,
                        startDate: selectedInterval.start,
                        endDate: reportExportEndDate,
                        transactionIDs: selectedTransactions.map(\\.id),
                        currencyCode: store.currencyCode,
                        reportTitle: kind.rawValue
                    )
                }
'''
report_download_new = '''                if !devEnabled || devShowReportDownload {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ReportDownloadButton(
                            type: kind.exportType,
                            startDate: selectedInterval.start,
                            endDate: reportExportEndDate,
                            transactionIDs: selectedTransactions.map(\\.id),
                            currencyCode: store.currencyCode,
                            reportTitle: kind.rawValue
                        )
                    }
                }
'''
text = must_replace(text, report_download, report_download_new, "report download toggle")

text = must_replace(
    text,
    '''                Text("\\(selectedTransactions.count) transactions")
                    .font(.caption)
                    .foregroundStyle(.secondary)''',
    '''                if !devEnabled || devShowTransactionCount {
                    Text("\\(selectedTransactions.count) transactions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }''',
    "period navigator transaction count",
)

text = must_replace(
    text,
    '''                ForEach(selectedTransactions.sorted { $0.date > $1.date }) { transaction in''',
    '''                ForEach(orderedReportTransactions) { transaction in''',
    "report transaction order",
)

footer_block = '''                Divider()
                HStack {
                    Text("Total · \\(selectedTransactions.count) transactions")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(DisplayFormat.currency(transactionListTotal, code: store.currencyCode))
                        .font(.headline)
                }
                .padding(.top, 4)
'''
footer_new = '''                if !devEnabled || devShowFooterTotal {
                    Divider()
                    HStack {
                        Text((!devEnabled || devShowTransactionCount) ? "Total · \\(selectedTransactions.count) transactions" : "Total")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(DisplayFormat.currency(transactionListTotal, code: store.currencyCode))
                            .font(.headline)
                    }
                    .padding(.top, 4)
                }
'''
text = must_replace(text, footer_block, footer_new, "report footer total")

# Rewrite activity chart to a reusable developer-configurable chart.
activity_start = '''    private var activityChart: some View {'''
activity_end = '''    private var categoryBreakdown: some View {'''
activity_replacement = '''    private var activityChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Activity")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if buckets.allSatisfy({ $0.income == 0 && $0.expense == 0 }) {
                EmptyLedgerView(
                    title: "Nothing to chart",
                    message: "Transactions in this period will appear here."
                )
            } else {
                DeveloperActivityChart(
                    points: buckets.map {
                        DeveloperChartPoint(
                            id: $0.id,
                            label: $0.label,
                            income: $0.income,
                            expense: $0.expense
                        )
                    }
                )
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .developerSurface()
    }

'''
text = replace_between(text, activity_start, activity_end, activity_replacement, "activity chart")

# Category limit + optional progress + depth.
text = must_replace(
    text,
    '''                ForEach(categoryTotals) { item in''',
    '''                ForEach(Array(categoryTotals.prefix(effectiveCategoryLimit))) { item in''',
    "category limit",
)
text = must_replace(
    text,
    '''                                ProgressView(value: categoryRatio(item.amount))
                                    .tint(AppTheme.categoryColor(item.name))''',
    '''                                if !devEnabled || devShowCategoryProgress {
                                    ProgressView(value: categoryRatio(item.amount))
                                        .tint(AppTheme.categoryColor(item.name))
                                }''',
    "category progress toggle",
)
text = must_replace(
    text,
    '''        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var selectedInterval:''',
    '''        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .developerSurface()
    }

    private var selectedInterval:''',
    "category developer surface",
)

# Add surface to transaction list container (the first matching block immediately before transactionListTotal).
text = must_replace(
    text,
    '''        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var transactionListTotal: Decimal {''',
    '''        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .developerSurface()
    }

    private var transactionListTotal: Decimal {''',
    "transaction list developer surface",
)

# Rewrite Financial Summary layout with live switches.
total_cards_start = '''    private var totalCards: some View {'''
total_cards_end = '''    private var closingBalanceAccounts: [LedgerAccount] {'''
total_cards_replacement = '''    private var totalCards: some View {
        VStack(spacing: effectiveReportBlockSpacing) {
            if !devEnabled || devShowSummaryNet {
                ReportTotalCard(
                    title: "Net Balance",
                    value: financeSummaryNetBalance,
                    currencyCode: store.currencyCode,
                    icon: "equal.circle.fill",
                    color: financeSummaryNetBalance >= 0 ? AppTheme.purple : AppTheme.red,
                    secondaryText: closingBalanceAccounts.isEmpty
                        ? nil
                        : "Includes opening balance: \\(DisplayFormat.currency(qatarClosingBalance, code: "QAR"))"
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .stroke(financeSummaryNetBalance >= 0 ? AppTheme.purple : AppTheme.red, lineWidth: 2.5)
                }
            }

            if !devEnabled || devShowSummaryRate {
                Text("PKR loan movement converted at fixed rate: PKR 77 = QAR 1.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !devEnabled || devShowSummaryConnectors {
                SummaryConnectorLines()
                    .frame(height: 38)
                    .padding(.horizontal, 46)
                    .accessibilityHidden(true)
            }

            if !devEnabled || devShowIncomeColumn || devShowExpenseColumn {
                HStack(alignment: .top, spacing: 12) {
                    if !devEnabled || devShowIncomeColumn {
                        moneyFlowColumn(
                            title: "Total Income",
                            color: AppTheme.green,
                            totalValue: totalMoneyIn,
                            primaryTitle: "Income",
                            primaryValue: financialSummaryDirectIncomeTotal,
                            primaryKind: .income,
                            movementTitle: "Loans Increased",
                            movements: loanIncreaseMovements
                        )
                    }
                    if !devEnabled || devShowExpenseColumn {
                        moneyFlowColumn(
                            title: "Total Money Out",
                            color: AppTheme.red,
                            totalValue: totalMoneyOut,
                            primaryTitle: "Expenses",
                            primaryValue: financialSummaryDirectExpenseTotal,
                            primaryKind: .expenses,
                            movementTitle: "Loans Paid",
                            movements: loanDecreaseMovements
                        )
                    }
                }
            }

            if !devEnabled || devShowCustomBalanceCards {
                ForEach(customSummaryCards) { card in
                    let accountCount = validAccountCount(card)
                    let timingLabel = customSummaryTimingLabel(card)
                    HStack(spacing: 8) {
                        Button {
                            editingSummaryCard = card
                        } label: {
                            FinanceSummaryBalanceCard(
                                title: customSummaryTitle(card),
                                value: customSummaryBalance(card),
                                currencyCode: card.currencyCode,
                                accountCount: accountCount,
                                timingLabel: timingLabel
                            )
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button {
                                editingSummaryCard = card
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleteCustomSummaryCard(card.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle.fill")
                                .font(.title2)
                                .frame(width: 42, height: 42)
                        }
                        .accessibilityLabel("Options for \\(customSummaryTitle(card))")
                    }
                }
            }

            if !devEnabled || devShowOpeningBalance {
                HStack {
                    Rectangle().frame(height: 2).foregroundStyle(AppTheme.purple)
                    Text("Opening Balance")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.purple)
                    Rectangle().frame(height: 2).foregroundStyle(AppTheme.purple)
                }
                .padding(.top, 2)

                Button {
                    editingClosingBalance = true
                } label: {
                    ReportTotalCard(
                        title: "Opening Balance as of \\(selectedInterval.start.formatted(date: .abbreviated, time: .omitted))",
                        value: qatarClosingBalance,
                        currencyCode: "QAR",
                        icon: "calendar.badge.clock",
                        color: AppTheme.purple,
                        secondaryText: closingBalanceAccounts.isEmpty
                            ? "Select Qatar accounts"
                            : closingBalanceAccounts.map(\\.name).joined(separator: " + ")
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .stroke(AppTheme.purple, lineWidth: 2.5)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit Qatar opening balance accounts")
            }
        }
    }

'''
text = replace_between(text, total_cards_start, total_cards_end, total_cards_replacement, "financial summary total cards")

# Sort loan currency cards using developer preference.
movement_rows_start = '''    private func movementRows(_ totals: [String: Decimal]) -> [LoanNetMovement] {'''
movement_rows_end = '''    private func convertedMovementTotal'''
movement_rows_replacement = '''    private func movementRows(_ totals: [String: Decimal]) -> [LoanNetMovement] {
        let values = totals.compactMap { currency, amount -> LoanNetMovement? in
            guard amount > 0 else { return nil }
            return LoanNetMovement(currencyCode: currency, netAmount: amount)
        }
        guard devEnabled else {
            return values.sorted { $0.currencyCode < $1.currencyCode }
        }
        switch DeveloperLoanSort(rawValue: devSummaryLoanSort) ?? .alphabetical {
        case .alphabetical:
            return values.sorted { $0.currencyCode < $1.currencyCode }
        case .qarFirst:
            return values.sorted {
                if $0.currencyCode.uppercased() == "QAR" { return true }
                if $1.currencyCode.uppercased() == "QAR" { return false }
                return $0.currencyCode < $1.currencyCode
            }
        case .largestFirst:
            return values.sorted { $0.netAmount > $1.netAmount }
        }
    }

    private func convertedMovementTotal'''
text = replace_between(text, movement_rows_start, movement_rows_end, movement_rows_replacement, "movement sorting")

# Rewrite money-flow column.
money_start = '''    private func moneyFlowColumn('''
money_end = '''    private func movementCard('''
money_replacement = '''    private func moneyFlowColumn(
        title: String,
        color: Color,
        totalValue: Decimal,
        primaryTitle: String,
        primaryValue: Decimal,
        primaryKind: PeriodTransactionKind,
        movementTitle: String,
        movements: [LoanNetMovement]
    ) -> some View {
        VStack(spacing: devEnabled && devSummaryCompactCards ? 6 : 8) {
            Text(title.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)

            ReportTotalCard(
                title: title,
                value: totalValue,
                currencyCode: store.currencyCode,
                icon: primaryKind == .income
                    ? "arrow.down.to.line.circle.fill"
                    : "arrow.up.to.line.circle.fill",
                color: color,
                compact: !devEnabled || devSummaryCompactCards
            )
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(color, lineWidth: 2.4)
            }

            if (!devEnabled || devShowSummaryOperators) && (!devEnabled || devShowPrimaryCards) {
                formulaOperator("=", color: color)
            }

            if !devEnabled || devShowPrimaryCards {
                NavigationLink {
                    PeriodTransactionsView(kind: primaryKind, interval: selectedInterval)
                } label: {
                    ReportTotalCard(
                        title: primaryTitle,
                        value: primaryValue,
                        currencyCode: store.currencyCode,
                        icon: primaryKind == .income
                            ? "arrow.down.left.circle.fill"
                            : "arrow.up.right.circle.fill",
                        color: color,
                        compact: !devEnabled || devSummaryCompactCards
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .stroke(color.opacity(0.65), lineWidth: 2)
                    }
                }
                .buttonStyle(.plain)
            }

            if primaryKind == .income && (!devEnabled || devShowRefunds) {
                if !devEnabled || devShowSummaryOperators { formulaOperator("+", color: color) }
                NavigationLink {
                    PeriodTransactionsView(kind: .refunds, interval: selectedInterval)
                } label: {
                    ReportTotalCard(
                        title: "Refunds",
                        value: financialSummaryRefundTotal,
                        currencyCode: store.currencyCode,
                        icon: "arrow.uturn.backward.circle.fill",
                        color: color,
                        compact: !devEnabled || devSummaryCompactCards
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .stroke(color.opacity(0.65), lineWidth: 2)
                    }
                }
                .buttonStyle(.plain)
            }

            if !devEnabled || devShowLoans {
                if !devEnabled || devShowSummaryOperators { formulaOperator("+", color: color) }
                if movements.isEmpty {
                    ReportTotalCard(
                        title: movementTitle,
                        value: 0,
                        currencyCode: store.currencyCode,
                        icon: primaryKind == .income
                            ? "arrow.up.right.circle.fill"
                            : "arrow.down.right.circle.fill",
                        color: color,
                        compact: !devEnabled || devSummaryCompactCards
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .stroke(color.opacity(0.65), lineWidth: 2)
                    }
                } else {
                    ForEach(Array(movements.enumerated()), id: \\.element.id) { index, movement in
                        if index > 0 && (!devEnabled || devShowSummaryOperators) {
                            formulaOperator("+", color: color)
                        }
                        NavigationLink {
                            financialSummaryMovementDestination(
                                primaryKind: primaryKind,
                                currencyCode: movement.currencyCode
                            )
                        } label: {
                            movementCard(
                                title: movementTitle,
                                movement: movement,
                                icon: primaryKind == .income
                                    ? "arrow.up.right.circle.fill"
                                    : "arrow.down.right.circle.fill",
                                color: color
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(devEnabled && devSummaryCompactCards ? 7 : 9)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(color.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(color.opacity(0.65), lineWidth: 2)
        }
        .developerSurface()
    }

'''
text = replace_between(text, money_start, money_end, money_replacement, "money flow column")

# PKR secondary conversion and compactness.
text = must_replace(
    text,
    '''            compact: true,
            secondaryText: movement.currencyCode.uppercased() == "PKR"
                ? "QAR: \\(DisplayFormat.currency(abs(movement.netAmount) / Decimal(77), code: "QAR"))"
                : nil''',
    '''            compact: !devEnabled || devSummaryCompactCards,
            secondaryText: (!devEnabled || devShowPKRConversion) && movement.currencyCode.uppercased() == "PKR"
                ? "QAR: \\(DisplayFormat.currency(abs(movement.netAmount) / Decimal(77), code: "QAR"))"
                : nil''',
    "movement PKR conversion toggle",
)

# Add report-layout helper properties before selectedInterval.
helper_anchor = '''    private var selectedInterval: DateInterval {'''
helpers = '''    private var effectiveReportBlockSpacing: CGFloat {
        guard devEnabled else { return 18 }
        switch DeveloperDensity(rawValue: devDensity) ?? .standard {
        case .compact: return CGFloat(min(devReportBlockSpacing, 12))
        case .standard: return CGFloat(devReportBlockSpacing)
        case .spacious: return CGFloat(max(devReportBlockSpacing, 24))
        }
    }

    private var effectiveReportPagePadding: CGFloat {
        guard devEnabled else { return 16 }
        switch DeveloperDensity(rawValue: devDensity) ?? .standard {
        case .compact: return CGFloat(min(devReportPagePadding, 12))
        case .standard: return CGFloat(devReportPagePadding)
        case .spacious: return CGFloat(max(devReportPagePadding, 20))
        }
    }

    private var effectiveCategoryLimit: Int {
        devEnabled ? max(1, min(50, devCategoryLimit)) : 50
    }

    private var orderedReportTransactions: [LedgerTransaction] {
        let newestFirst = !devEnabled || devTransactionOrder == DeveloperTransactionOrder.newest.rawValue
        return selectedTransactions.sorted { newestFirst ? ($0.date > $1.date) : ($0.date < $1.date) }
    }

'''
text = must_replace(text, helper_anchor, helpers + helper_anchor, "report helper properties")

# ReportTotalCard: dynamic corner radius + global developer depth.
report_card_anchor = '''private struct ReportTotalCard: View {
    let title: String
    let value: Decimal
    let currencyCode: String
    let icon: String
    let color: Color
    var compact = false
    var secondaryText: String? = nil

    var body: some View {'''
report_card_new = '''private struct ReportTotalCard: View {
    let title: String
    let value: Decimal
    let currencyCode: String
    let icon: String
    let color: Color
    var compact = false
    var secondaryText: String? = nil
    @AppStorage(DeveloperLabKey.enabled) private var devEnabled = true
    @AppStorage(DeveloperLabKey.cardCornerRadius) private var devCornerRadius = 20.0

    var body: some View {'''
text = must_replace(text, report_card_anchor, report_card_new, "report total card props")
text = must_replace(
    text,
    '''        .background(.background, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}

private struct FinanceSummaryBalanceCard:''',
    '''        .background(.background, in: RoundedRectangle(cornerRadius: devEnabled ? CGFloat(devCornerRadius) : 19, style: .continuous))
        .developerSurface()
    }
}

private struct FinanceSummaryBalanceCard:''',
    "report total card surface",
)

# Add depth to custom balance cards as well.
text = must_replace(
    text,
    '''        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {''',
    '''        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .developerSurface()
        .overlay {''',
    "finance custom card surface",
)

reports.write_text(text)

# Components: BalanceCard geometry + transaction row switches.
components = Path("DailyLedger/Views/Components.swift")
text = components.read_text()
text = must_replace(
    text,
    '''struct BalanceCard: View {
    let balance: Decimal''',
    '''struct BalanceCard: View {
    @AppStorage(DeveloperLabKey.enabled) private var devEnabled = true
    @AppStorage(DeveloperLabKey.cardCornerRadius) private var devCornerRadius = 28.0
    let balance: Decimal''',
    "balance card dev props",
)
text = must_replace(
    text,
    '''        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))''',
    '''        .clipShape(RoundedRectangle(cornerRadius: devEnabled ? CGFloat(devCornerRadius) : 28, style: .continuous))
        .developerSurface()''',
    "balance card depth",
)

transaction_anchor = '''struct TransactionRow: View {
    @EnvironmentObject private var store: LedgerStore
    let transaction: LedgerTransaction
    var accountID: UUID? = nil

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: AppTheme.categoryIcon(transaction.category))'''
transaction_new = '''struct TransactionRow: View {
    @EnvironmentObject private var store: LedgerStore
    @AppStorage(DeveloperLabKey.enabled) private var devEnabled = true
    @AppStorage(DeveloperLabKey.density) private var devDensity = DeveloperDensity.standard.rawValue
    @AppStorage(DeveloperLabKey.transactionShowIcon) private var devShowIcon = true
    @AppStorage(DeveloperLabKey.transactionShowDate) private var devShowDate = true
    @AppStorage(DeveloperLabKey.transactionShowSecondary) private var devShowSecondary = true
    @AppStorage(DeveloperLabKey.transactionShowRunningBalance) private var devShowRunningBalance = true
    @AppStorage(DeveloperLabKey.transactionShowTransferSecondary) private var devShowTransferSecondary = true
    @AppStorage(DeveloperLabKey.transactionCompactRows) private var devCompactRows = false
    let transaction: LedgerTransaction
    var accountID: UUID? = nil

    var body: some View {
        HStack(spacing: effectiveCompactRow ? 9 : 13) {
            if !devEnabled || devShowIcon {
            Image(systemName: AppTheme.categoryIcon(transaction.category))'''
text = must_replace(text, transaction_anchor, transaction_new, "transaction row props")
text = must_replace(
    text,
    '''                )

            VStack(alignment: .leading, spacing: 4) {''',
    '''                )
            }

            VStack(alignment: .leading, spacing: effectiveCompactRow ? 2 : 4) {''',
    "transaction icon close",
)
text = must_replace(
    text,
    '''                Text(secondaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)''',
    '''                if !devEnabled || devShowSecondary {
                    Text(secondaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }''',
    "transaction secondary toggle",
)
text = must_replace(
    text,
    '''                Text(transaction.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)''',
    '''                if !devEnabled || devShowDate {
                    Text(transaction.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }''',
    "transaction date toggle",
)
text = must_replace(
    text,
    '''                if accountID == nil,
                   transaction.type == .transfer,
                   let destination = destinationAccount {''',
    '''                if (!devEnabled || devShowTransferSecondary),
                   accountID == nil,
                   transaction.type == .transfer,
                   let destination = destinationAccount {''',
    "transaction transfer secondary toggle",
)
text = must_replace(
    text,
    '''                if let runningBalance = store.runningBalance(''',
    '''                if (!devEnabled || devShowRunningBalance),
                   let runningBalance = store.runningBalance(''',
    "transaction running balance toggle",
)
text = must_replace(
    text,
    '''        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private var amountText: String {''',
    '''        .padding(.vertical, effectiveCompactRow ? 2 : 5)
        .accessibilityElement(children: .combine)
    }

    private var effectiveCompactRow: Bool {
        guard devEnabled else { return false }
        if devCompactRows { return true }
        return devDensity == DeveloperDensity.compact.rawValue
    }

    private var amountText: String {''',
    "transaction row compact helper",
)
components.write_text(text)

# Dashboard section visibility, layout and recent limit.
dashboard = Path("DailyLedger/Views/DashboardView.swift")
text = dashboard.read_text()
dashboard_props_anchor = '''    @AppStorage("DashboardSpendingCardOrder") private var storedCardOrder = "yesterday,today,thisWeek,lastWeek"
    @State private var dashboardSnapshot = DashboardSnapshot.empty
'''
dashboard_props_new = '''    @AppStorage("DashboardSpendingCardOrder") private var storedCardOrder = "yesterday,today,thisWeek,lastWeek"
    @AppStorage(DeveloperLabKey.enabled) private var devEnabled = true
    @AppStorage(DeveloperLabKey.dashboardShowHeader) private var devShowHeader = true
    @AppStorage(DeveloperLabKey.dashboardShowSpending) private var devShowSpending = true
    @AppStorage(DeveloperLabKey.dashboardShowDateFilter) private var devShowDateFilter = true
    @AppStorage(DeveloperLabKey.dashboardShowBalance) private var devShowBalance = true
    @AppStorage(DeveloperLabKey.dashboardShowQuickActions) private var devShowQuickActions = true
    @AppStorage(DeveloperLabKey.dashboardShowRecent) private var devShowRecent = true
    @AppStorage(DeveloperLabKey.dashboardColumns) private var devDashboardColumns = 2
    @AppStorage(DeveloperLabKey.dashboardHorizontalPadding) private var devDashboardHorizontalPadding = 18.0
    @AppStorage(DeveloperLabKey.dashboardSectionSpacing) private var devDashboardSectionSpacing = 22.0
    @AppStorage(DeveloperLabKey.dashboardRecentLimit) private var devDashboardRecentLimit = 6
    @State private var dashboardSnapshot = DashboardSnapshot.empty
'''
text = must_replace(text, dashboard_props_anchor, dashboard_props_new, "dashboard dev props")

dashboard_body = '''                LazyVStack(alignment: .leading, spacing: 22) {
                    header
                    dailySpending
                    dateFilter
                    BalanceCard(
                        balance: dashboardSnapshot.balance,
                        income: dashboardSnapshot.totals.income,
                        expense: dashboardSnapshot.totals.expense,
                        loanMovements: dashboardSnapshot.loanMovements,
                        currencyCode: store.currencyCode,
                        accountSummary: accountSelectionTitle,
                        action: { showingAccountSelection = true }
                    )
                    quickActions
                    recentTransactions
                }
                .padding(.horizontal, 18)
'''
dashboard_body_new = '''                LazyVStack(alignment: .leading, spacing: effectiveDashboardSectionSpacing) {
                    if !devEnabled || devShowHeader { header }
                    if !devEnabled || devShowSpending { dailySpending }
                    if !devEnabled || devShowDateFilter { dateFilter }
                    if !devEnabled || devShowBalance {
                        BalanceCard(
                            balance: dashboardSnapshot.balance,
                            income: dashboardSnapshot.totals.income,
                            expense: dashboardSnapshot.totals.expense,
                            loanMovements: dashboardSnapshot.loanMovements,
                            currencyCode: store.currencyCode,
                            accountSummary: accountSelectionTitle,
                            action: { showingAccountSelection = true }
                        )
                    }
                    if !devEnabled || devShowQuickActions { quickActions }
                    if !devEnabled || devShowRecent { recentTransactions }
                }
                .padding(.horizontal, effectiveDashboardHorizontalPadding)
'''
text = must_replace(text, dashboard_body, dashboard_body_new, "dashboard section visibility")
text = must_replace(
    text,
    '''            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {''',
    '''            LazyVGrid(columns: effectiveDashboardGridColumns, spacing: 12) {''',
    "dashboard grid columns",
)
text = must_replace(
    text,
    '''ForEach(Array(dashboardSnapshot.recentTransactions.prefix(6).enumerated()), id: \\.element.id)''',
    '''ForEach(Array(dashboardSnapshot.recentTransactions.prefix(effectiveDashboardRecentLimit).enumerated()), id: \\.element.id)''',
    "dashboard recent prefix",
)
text = must_replace(
    text,
    '''if index < min(dashboardSnapshot.recentTransactions.count, 6) - 1 {''',
    '''if index < min(dashboardSnapshot.recentTransactions.count, effectiveDashboardRecentLimit) - 1 {''',
    "dashboard recent divider",
)

helper_anchor = '''    private var selectedDatePreset: DashboardDatePreset {'''
dashboard_helpers = '''    private var effectiveDashboardSectionSpacing: CGFloat {
        devEnabled ? CGFloat(max(4, min(40, devDashboardSectionSpacing))) : 22
    }

    private var effectiveDashboardHorizontalPadding: CGFloat {
        devEnabled ? CGFloat(max(0, min(32, devDashboardHorizontalPadding))) : 18
    }

    private var effectiveDashboardGridColumns: [GridItem] {
        let count = devEnabled ? max(1, min(3, devDashboardColumns)) : 2
        return Array(repeating: GridItem(.flexible()), count: count)
    }

    private var effectiveDashboardRecentLimit: Int {
        devEnabled ? max(1, min(20, devDashboardRecentLimit)) : 6
    }

'''
text = must_replace(text, helper_anchor, dashboard_helpers + helper_anchor, "dashboard helpers")

# Give spending and quick-action cards the same 2D/3D developer surface.
text = must_replace(
    text,
    '''            if visualTheme == AppVisualTheme.glass.rawValue { cardContent.dailyLedgerGlass(tint: colors.first ?? AppTheme.purple, interactive: true) }
            else { cardContent }
        }
        }''',
    '''            if visualTheme == AppVisualTheme.glass.rawValue { cardContent.dailyLedgerGlass(tint: colors.first ?? AppTheme.purple, interactive: true) }
            else { cardContent }
        }
        .developerSurface()
        }''',
    "daily spend developer surface",
)
text = must_replace(
    text,
    '''            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}''',
    '''            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .developerSurface()
        }
        .buttonStyle(.plain)
    }
}''',
    "quick action developer surface",
)
dashboard.write_text(text)

print("Prepared Next Ledger 1.3.71 build 79: Developer Lab with live 2D/3D, chart, report, Financial Summary, dashboard and transaction-row customization.")
