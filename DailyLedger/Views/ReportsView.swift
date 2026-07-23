import Charts
import SwiftUI

private enum ReportPeriod: String, CaseIterable, Identifiable {
    case day = "Daily"
    case month = "Monthly"
    case year = "Yearly"
    case custom = "Custom"
    var id: String { rawValue }
}

private enum ReportKind: String, CaseIterable, Identifiable {
    case summary = "Financial Summary"
    case income = "Income Report"
    case expenses = "Expense Report"
    case loans = "Loans / Transfers"
    case categories = "Category Report"

    var id: String { rawValue }
    var subtitle: String {
        switch self {
        case .summary: return "Income, expenses, transfers and net result"
        case .income: return "All money received in the selected period"
        case .expenses: return "All expenses with transaction snapshots"
        case .loans: return "Amounts transferred out during the selected period"
        case .categories: return "Spending grouped by category"
        }
    }
    var icon: String {
        switch self {
        case .summary: return "chart.bar.xaxis"
        case .income: return "arrow.down.left.circle.fill"
        case .expenses: return "arrow.up.right.circle.fill"
        case .loans: return "arrow.left.arrow.right.circle.fill"
        case .categories: return "square.grid.2x2.fill"
        }
    }
}

private struct ReportBucket: Identifiable {
    let id: String
    let label: String
    let income: Double
    let expense: Double
}

private struct CategoryTotal: Identifiable {
    let id: String
    let name: String
    let amount: Decimal
}

struct ReportsView: View {
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Planning & Comparison") {
                    NavigationLink { ReportComparisonView() } label: {
                        Label("Compare Reports", systemImage: "chart.xyaxis.line")
                    }
                    NavigationLink { BudgetReportView() } label: {
                        Label("Budget Planner", systemImage: "target")
                    }
                    NavigationLink { CustomAccountReportView() } label: {
                        Label("Custom Account Report", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink { LoanMovementReportView() } label: {
                        Label("Loan Movement by Currency", systemImage: "banknote.fill")
                    }
                }
                Section {
                    ForEach(filteredReportKinds) { kind in
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
                } header: {
                    Text("Choose a report")
                } footer: {
                    Text("Select a report first, then choose its month or year.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Reports")
            .searchable(text: $searchText, prompt: "Search reports")
        }
    }

    private var filteredReportKinds: [ReportKind] {
        guard !searchText.isEmpty else { return ReportKind.allCases }
        return ReportKind.allCases.filter {
            $0.rawValue.localizedCaseInsensitiveContains(searchText) ||
            $0.subtitle.localizedCaseInsensitiveContains(searchText)
        }
    }
}

private struct ReportComparisonView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var period: ReportPeriod = .month
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEnd = Date()

    var body: some View {
        List {
            Picker("Period", selection: $period) {
                ForEach(ReportPeriod.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu)
            if period == .custom {
                Section("Custom Dates") {
                    DatePicker("From", selection: $customStart, displayedComponents: .date)
                    DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date)
                }
            }
            Section("Current vs Previous") {
                comparisonHeader
                comparisonRow("Current", interval: currentInterval)
                comparisonRow("Previous", interval: previousInterval)
                comparisonValues(
                    title: "Change",
                    income: amount(.income, in: currentInterval) - amount(.income, in: previousInterval),
                    expense: amount(.expense, in: currentInterval) - amount(.expense, in: previousInterval)
                )
            }
        }
        .navigationTitle("Compare Reports")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var calendarUnit: Calendar.Component {
        switch period { case .day: return .day; case .year: return .year; default: return .month }
    }
    private var currentInterval: DateInterval {
        if period == .custom {
            return DateInterval(
                start: Calendar.current.startOfDay(for: customStart),
                end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: customEnd))!
            )
        }
        return Calendar.current.dateInterval(of: calendarUnit, for: Date())!
    }
    private var previousInterval: DateInterval {
        if period == .custom {
            let duration = currentInterval.duration
            return DateInterval(start: currentInterval.start.addingTimeInterval(-duration), end: currentInterval.start)
        }
        let date = Calendar.current.date(byAdding: calendarUnit, value: -1, to: Date())!
        return Calendar.current.dateInterval(of: calendarUnit, for: date)!
    }
    private func amount(_ type: TransactionType, in interval: DateInterval) -> Decimal {
        store.transactions.lazy.filter {
            $0.type == type && interval.contains($0.date) && store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
        }.reduce(Decimal.zero) { $0 + $1.amount }
    }
    private var comparisonHeader: some View {
        HStack {
            Text("Period").frame(maxWidth: .infinity, alignment: .leading)
            Text("Income").frame(width: 100, alignment: .trailing)
            Text("Expense").frame(width: 100, alignment: .trailing)
        }.font(.caption.bold()).foregroundStyle(.secondary)
    }
    private func comparisonRow(_ title: String, interval: DateInterval) -> some View {
        NavigationLink {
            ComparisonTransactionsView(interval: interval)
        } label: {
            comparisonValues(
                title: "\(title)\n\(transactionCount(in: interval)) trans.",
                income: amount(.income, in: interval),
                expense: amount(.expense, in: interval)
            )
        }
    }
    private func comparisonValues(title: String, income: Decimal, expense: Decimal) -> some View {
        HStack {
            Text(title).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            Text(DisplayFormat.currency(income, code: store.currencyCode))
                .font(.caption.bold()).frame(width: 100, alignment: .trailing)
            Text(DisplayFormat.currency(expense, code: store.currencyCode))
                .font(.caption.bold()).frame(width: 100, alignment: .trailing)
        }.minimumScaleFactor(0.65)
    }
    private func transactionCount(in interval: DateInterval) -> Int {
        store.transactions.lazy.filter {
            ($0.type == .income || $0.type == .expense) && interval.contains($0.date) &&
            store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
        }.count
    }
}

private struct BudgetReportView: View {
    @EnvironmentObject private var store: LedgerStore
    @AppStorage("MonthlyIncomePrimary") private var primaryIncome = 0.0
    @AppStorage("MonthlyIncomeSecondary") private var secondaryIncome = 0.0
    var body: some View {
        List {
            Section("Monthly Income") {
                Stepper("Primary: \(DisplayFormat.currency(Decimal(primaryIncome), code: store.currencyCode))", value: $primaryIncome, in: 0...1_000_000, step: 500)
                Stepper("Other fixed: \(DisplayFormat.currency(Decimal(secondaryIncome), code: store.currencyCode))", value: $secondaryIncome, in: 0...1_000_000, step: 500)
            }
            Section("Suggested Budget") {
                budget("Essentials", 0.45); budget("Savings & goals", 0.20)
                budget("Family & flexible", 0.20); budget("Personal", 0.10); budget("Buffer", 0.05)
            }
        }
        .navigationTitle("Budget Planner")
        .navigationBarTitleDisplayMode(.inline)
    }
    private var total: Decimal { Decimal(primaryIncome + secondaryIncome) }
    private func budget(_ title: String, _ ratio: Decimal) -> some View {
        LabeledContent(title, value: DisplayFormat.currency(total * ratio, code: store.currencyCode))
    }
}

private struct CustomAccountReportView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var selected = Set<UUID>()
    @State private var start = Calendar.current.dateInterval(of: .month, for: Date())!.start
    @State private var end = Date()
    @State private var compare = true

    var body: some View {
        List {
            Section("Accounts") {
                HStack {
                    Button("Select All") { selected = Set(store.activeAccounts.map(\.id)) }
                    Spacer()
                    Button("Deselect All") { selected.removeAll() }
                }
                ForEach(store.activeAccounts) { account in
                    Button { toggle(account.id) } label: {
                        HStack {
                            Label(account.name, systemImage: account.icon)
                            Spacer()
                            if selected.contains(account.id) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.purple)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Section("Dates") {
                DatePicker("From", selection: $start, displayedComponents: .date)
                DatePicker("To", selection: $end, in: start..., displayedComponents: .date)
                Toggle("Compare previous period", isOn: $compare)
            }
            Section("Selected Period") {
                accountComparisonHeader
                accountComparisonRow("Selected", interval: interval)
            }
            if compare {
                Section("Previous Equal Period") {
                    accountComparisonHeader
                    accountComparisonRow("Previous", interval: previousInterval)
                    accountValues(
                        "Change",
                        income: total(.income, in: interval) - total(.income, in: previousInterval),
                        expense: total(.expense, in: interval) - total(.expense, in: previousInterval)
                    )
                }
            }
        }
        .navigationTitle("Custom Account Report")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if selected.isEmpty { selected = Set(store.activeAccounts.map(\.id)) } }
    }

    private var interval: DateInterval {
        DateInterval(start: Calendar.current.startOfDay(for: start),
                     end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end))!)
    }
    private var previousInterval: DateInterval {
        DateInterval(start: interval.start.addingTimeInterval(-interval.duration), end: interval.start)
    }
    private func transactions(in interval: DateInterval) -> [LedgerTransaction] {
        store.transactions.filter { interval.contains($0.date) && selected.contains($0.accountID ?? LedgerAccount.legacyMainID) }
    }
    private func total(_ type: TransactionType, in interval: DateInterval) -> Decimal {
        transactions(in: interval).filter { $0.type == type }.reduce(0) { $0 + $1.amount }
    }
    private func formatted(_ value: Decimal) -> String { DisplayFormat.currency(value, code: store.currencyCode) }
    private var accountComparisonHeader: some View {
        HStack {
            Text("Period").frame(maxWidth: .infinity, alignment: .leading)
            Text("Income").frame(width: 100, alignment: .trailing)
            Text("Expense").frame(width: 100, alignment: .trailing)
        }.font(.caption.bold()).foregroundStyle(.secondary)
    }
    private func accountComparisonRow(_ title: String, interval: DateInterval) -> some View {
        NavigationLink {
            AccountReportTransactionsView(interval: interval, accountIDs: selected)
        } label: {
            accountValues("\(title)\n\(transactions(in: interval).count) trans.",
                          income: total(.income, in: interval), expense: total(.expense, in: interval))
        }
    }
    private func accountValues(_ title: String, income: Decimal, expense: Decimal) -> some View {
        HStack {
            Text(title).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            Text(formatted(income)).font(.caption.bold()).frame(width: 100, alignment: .trailing)
            Text(formatted(expense)).font(.caption.bold()).frame(width: 100, alignment: .trailing)
        }.minimumScaleFactor(0.65)
    }
    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
}

private struct LoanMovementReportView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var month = Date()
    @State private var customDates = false
    @State private var start = Calendar.current.dateInterval(of: .month, for: Date())!.start
    @State private var end = Date()

    var body: some View {
        List {
            Section {
                Toggle("Custom Date Range", isOn: $customDates)
                if customDates {
                    DatePicker("From", selection: $start, displayedComponents: .date)
                    DatePicker("To", selection: $end, in: start..., displayedComponents: .date)
                } else {
                    DatePicker("Month", selection: $month, displayedComponents: [.date])
                        .datePickerStyle(.compact)
                }
            }
            ForEach(currencies, id: \.self) { currency in
                Section(currency) {
                    LabeledContent("Loan increased", value: DisplayFormat.currency(increased(currency), code: currency))
                    LabeledContent("Loan paid", value: DisplayFormat.currency(paid(currency), code: currency))
                    LabeledContent("Net movement", value: DisplayFormat.currency(increased(currency) - paid(currency), code: currency))
                }
            }
        }
        .navigationTitle("Loan Movement")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var interval: DateInterval {
        if customDates {
            return DateInterval(start: Calendar.current.startOfDay(for: start),
                end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end))!)
        }
        return Calendar.current.dateInterval(of: .month, for: month)!
    }
    private var loanAccounts: [LedgerAccount] {
        store.accounts.filter { $0.group == .payments || $0.nature == .loan }
    }
    private var currencies: [String] {
        let values = Set(loanAccounts.map(\.currencyCode))
        return values.isEmpty ? ["QAR", "PKR"] : values.sorted()
    }
    private func increased(_ currency: String) -> Decimal {
        let ids = Set(loanAccounts.filter { $0.currencyCode == currency }.map(\.id))
        return store.transactions.filter {
            $0.type == .expense && interval.contains($0.date) && ids.contains($0.accountID ?? LedgerAccount.legacyMainID)
        }.reduce(0) { $0 + $1.amount }
    }
    private func paid(_ currency: String) -> Decimal {
        let ids = Set(loanAccounts.filter { $0.currencyCode == currency }.map(\.id))
        return store.transactions.filter {
            $0.type == .transfer && interval.contains($0.date) && ids.contains($0.destinationAccountID ?? LedgerAccount.legacyMainID)
        }.reduce(0) { total, item in
            total + (item.destinationAmount ?? item.amount)
        }
    }
}

private struct ReportDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    let kind: ReportKind
    @AppStorage("ReportPeriodSelection") private var storedPeriod = ReportPeriod.month.rawValue
    @AppStorage("ReportCustomStart") private var storedCustomStart = Date().timeIntervalSince1970
    @AppStorage("ReportCustomEnd") private var storedCustomEnd = Date().timeIntervalSince1970
    @State private var anchorDate = Date()
    @State private var selectedTransaction: LedgerTransaction?
    @State private var showingCustomDates = false
    @State private var draftStartDate = Date()
    @State private var draftEndDate = Date()
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    Picker("Report period", selection: $storedPeriod) {
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
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(AppTheme.page)
            .navigationTitle(kind.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search report transactions")
            .onChange(of: storedPeriod) { value in
                anchorDate = Date()
                if value == ReportPeriod.custom.rawValue {
                    draftStartDate = Date(timeIntervalSince1970: storedCustomStart)
                    draftEndDate = Date(timeIntervalSince1970: storedCustomEnd)
                    showingCustomDates = true
                }
            }
            .sheet(item: $selectedTransaction) { transaction in
                TransactionSnapshotView(transaction: transaction)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showingCustomDates) {
                NavigationStack {
                    Form {
                        DatePicker("From", selection: $draftStartDate, displayedComponents: .date)
                        DatePicker("To", selection: $draftEndDate, displayedComponents: .date)
                    }
                    .navigationTitle("Custom Report Period")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingCustomDates = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                storedCustomStart = draftStartDate.timeIntervalSince1970
                                storedCustomEnd = draftEndDate.timeIntervalSince1970
                                storedPeriod = ReportPeriod.custom.rawValue
                                showingCustomDates = false
                            }
                        }
                    }
                }
            }
        }
    }

    private var transactionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind.rawValue)
                .font(.headline)
            if selectedTransactions.isEmpty {
                EmptyLedgerView(
                    title: "No transactions",
                    message: "Nothing is available for this report period."
                )
            } else {
                ForEach(selectedTransactions.sorted { $0.date > $1.date }) { transaction in
                    Button {
                        selectedTransaction = transaction
                    } label: {
                        TransactionRow(transaction: transaction)
                    }
                    .buttonStyle(.plain)
                    if transaction.id != selectedTransactions.last?.id { Divider() }
                }
                Divider()
                HStack {
                    Text("Total · \(selectedTransactions.count) transactions")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(DisplayFormat.currency(transactionListTotal, code: store.currencyCode))
                        .font(.headline)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var transactionListTotal: Decimal {
        selectedTransactions.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var periodNavigator: some View {
        HStack {
            Button { movePeriod(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 40, height: 40)
                    .background(.background, in: Circle())
            }
            .disabled(selectedPeriod == .custom)
            .opacity(selectedPeriod == .custom ? 0.35 : 1)
            Spacer()
            VStack(spacing: 2) {
                Text(periodTitle)
                    .font(.headline)
                Text("\(selectedTransactions.count) transactions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { movePeriod(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 40, height: 40)
                    .background(.background, in: Circle())
            }
            .disabled(isCurrentPeriod || selectedPeriod == .custom)
            .opacity(isCurrentPeriod || selectedPeriod == .custom ? 0.35 : 1)
        }
    }

    private var totalCards: some View {
        VStack(spacing: 12) {
            ReportTotalCard(
                title: "Net Balance",
                value: totals.balance,
                currencyCode: store.currencyCode,
                icon: "equal.circle.fill",
                color: totals.balance >= 0 ? AppTheme.purple : AppTheme.red
            )
            HStack(spacing: 12) {
                NavigationLink {
                    PeriodTransactionsView(kind: .income, interval: selectedInterval)
                } label: {
                    ReportTotalCard(
                        title: "Income",
                        value: totals.income,
                        currencyCode: store.currencyCode,
                        icon: "arrow.down.left.circle.fill",
                        color: AppTheme.green,
                        compact: true
                    )
                }
                .buttonStyle(.plain)
                NavigationLink {
                    PeriodTransactionsView(kind: .expenses, interval: selectedInterval)
                } label: {
                    ReportTotalCard(
                        title: "Expenses",
                        value: totals.expense,
                        currencyCode: store.currencyCode,
                        icon: "arrow.up.right.circle.fill",
                        color: AppTheme.red,
                        compact: true
                    )
                }
                .buttonStyle(.plain)
            }
            NavigationLink {
                PeriodTransactionsView(kind: .loans, interval: selectedInterval)
            } label: {
                ReportTotalCard(
                    title: "Loans Paid",
                    value: totals.loan,
                    currencyCode: store.currencyCode,
                    icon: "banknote.fill",
                    color: AppTheme.orange
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var activityChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()
                HStack(spacing: 12) {
                    ChartLegend(color: AppTheme.green, title: "Income")
                    ChartLegend(color: AppTheme.red, title: "Expense")
                }
            }

            if buckets.allSatisfy({ $0.income == 0 && $0.expense == 0 }) {
                EmptyLedgerView(
                    title: "Nothing to chart",
                    message: "Transactions in this period will appear here."
                )
            } else {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Period", bucket.label),
                        y: .value("Income", bucket.income)
                    )
                    .foregroundStyle(AppTheme.green.gradient)
                    .position(by: .value("Type", "Income"))
                    .cornerRadius(3)

                    BarMark(
                        x: .value("Period", bucket.label),
                        y: .value("Expense", bucket.expense)
                    )
                    .foregroundStyle(AppTheme.red.gradient)
                    .position(by: .value("Type", "Expense"))
                    .cornerRadius(3)
                }
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 230)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Spending by category")
                .font(.headline)

            if categoryTotals.isEmpty {
                Text("No expenses in this period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ForEach(categoryTotals) { item in
                    NavigationLink {
                        CategoryTransactionsView(
                            category: item.name,
                            interval: selectedInterval
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: AppTheme.categoryIcon(item.name))
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.categoryColor(item.name))
                                .frame(width: 34, height: 34)
                                .background(AppTheme.categoryColor(item.name).opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.name)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(DisplayFormat.currency(item.amount, code: store.currencyCode))
                                        .font(.subheadline.bold())
                                }
                                ProgressView(value: categoryRatio(item.amount))
                                    .tint(AppTheme.categoryColor(item.name))
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Divider()
                HStack {
                    Text("Total Expenses").font(.headline)
                    Spacer()
                    Text(DisplayFormat.currency(totals.expense, code: store.currencyCode))
                        .font(.headline)
                }
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var selectedInterval: DateInterval {
        let calendar = Calendar.current
        if selectedPeriod == .custom {
            let first = Date(timeIntervalSince1970: storedCustomStart)
            let second = Date(timeIntervalSince1970: storedCustomEnd)
            let start = calendar.startOfDay(for: min(first, second))
            let endDay = calendar.startOfDay(for: max(first, second))
            return DateInterval(
                start: start,
                end: calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
            )
        }
        let component: Calendar.Component = selectedPeriod == .day ? .day : (selectedPeriod == .month ? .month : .year)
        return calendar.dateInterval(of: component, for: anchorDate)
            ?? DateInterval(start: anchorDate, duration: 1)
    }

    private var selectedTransactions: [LedgerTransaction] {
        store.transactions.filter {
            guard selectedInterval.contains($0.date),
                  store.account(withID: $0.accountID)?.currencyCode == store.currencyCode else {
                return false
            }
            let kindMatches: Bool
            switch kind {
            case .summary, .categories: kindMatches = true
            case .income: kindMatches = $0.type == .income
            case .expenses: kindMatches = $0.type == .expense
            case .loans:
                kindMatches = $0.type == .transfer &&
                    store.account(withID: $0.destinationAccountID)?.group == .payments
            }
            guard kindMatches, !searchText.isEmpty else { return kindMatches }
            return $0.category.localizedCaseInsensitiveContains(searchText) ||
                ($0.vendor?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                $0.details.localizedCaseInsensitiveContains(searchText) ||
                NSDecimalNumber(decimal: $0.amount).stringValue.contains(searchText)
        }
    }

    private var totals: LedgerTotals {
        store.totals(in: selectedInterval)
    }

    private var periodTitle: String {
        switch selectedPeriod {
        case .day: return DisplayFormat.day.string(from: anchorDate)
        case .month: return DisplayFormat.monthYear.string(from: anchorDate)
        case .year: return DisplayFormat.year.string(from: anchorDate)
        case .custom:
            return "\(DisplayFormat.day.string(from: selectedInterval.start)) – \(DisplayFormat.day.string(from: selectedInterval.end.addingTimeInterval(-1)))"
        }
    }

    private var isCurrentPeriod: Bool {
        let calendar = Calendar.current
        if selectedPeriod == .day {
            return calendar.isDateInToday(anchorDate)
        }
        if selectedPeriod == .month {
            return calendar.isDate(anchorDate, equalTo: Date(), toGranularity: .month)
        }
        if selectedPeriod == .custom { return true }
        return calendar.isDate(anchorDate, equalTo: Date(), toGranularity: .year)
    }

    private var buckets: [ReportBucket] {
        let calendar = Calendar.current
        if selectedPeriod == .day {
            return makeHourlyBuckets()
        }
        if selectedPeriod == .month || selectedPeriod == .custom {
            if selectedPeriod == .custom {
                let grouped = Dictionary(grouping: selectedTransactions) {
                    calendar.startOfDay(for: $0.date)
                }
                return grouped.keys.sorted().map { date in
                    makeBucket(
                        id: "custom-\(date.timeIntervalSince1970)",
                        label: DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none),
                        items: grouped[date, default: []]
                    )
                }
            }
            let days = calendar.range(of: .day, in: .month, for: anchorDate) ?? 1..<2
            return days.map { day in
                let items = selectedTransactions.filter {
                    calendar.component(.day, from: $0.date) == day
                }
                return makeBucket(id: "day-\(day)", label: "\(day)", items: items)
            }
        }

        let monthSymbols = calendar.shortMonthSymbols
        return (1...12).map { month in
            let items = selectedTransactions.filter {
                calendar.component(.month, from: $0.date) == month
            }
            return makeBucket(
                id: "month-\(month)",
                label: String(monthSymbols[month - 1].prefix(3)),
                items: items
            )
        }
    }

    private var categoryTotals: [CategoryTotal] {
        let expenses = selectedTransactions.filter { $0.type == .expense }
        let grouped = Dictionary(grouping: expenses, by: \.category)
        return grouped.map { category, items in
            CategoryTotal(
                id: category,
                name: category,
                amount: items.reduce(Decimal.zero) { $0 + $1.amount }
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    private func makeBucket(id: String, label: String, items: [LedgerTransaction]) -> ReportBucket {
        let income = items.filter { $0.type == .income }.reduce(Decimal.zero) { $0 + $1.amount }
        let expense = items.filter { $0.type == .expense }.reduce(Decimal.zero) { $0 + $1.amount }
        return ReportBucket(
            id: id,
            label: label,
            income: NSDecimalNumber(decimal: income).doubleValue,
            expense: NSDecimalNumber(decimal: expense).doubleValue
        )
    }

    private func categoryRatio(_ amount: Decimal) -> Double {
        guard totals.expense > 0 else { return 0 }
        return NSDecimalNumber(decimal: amount / totals.expense).doubleValue
    }

    private func movePeriod(_ direction: Int) {
        guard selectedPeriod != .custom, !(direction > 0 && isCurrentPeriod) else { return }
        let component: Calendar.Component = selectedPeriod == .day ? .day : (selectedPeriod == .month ? .month : .year)
        anchorDate = Calendar.current.date(byAdding: component, value: direction, to: anchorDate) ?? anchorDate
    }

    private func makeHourlyBuckets() -> [ReportBucket] {
        let calendar = Calendar.current
        return stride(from: 0, to: 24, by: 3).map { hour in
            let items = selectedTransactions.filter {
                let value = calendar.component(.hour, from: $0.date)
                return value >= hour && value < hour + 3
            }
            return makeBucket(id: "hour-\(hour)", label: String(format: "%02d:00", hour), items: items)
        }
    }

    private var selectedPeriod: ReportPeriod {
        ReportPeriod(rawValue: storedPeriod) ?? .month
    }
}

private struct ReportTotalCard: View {
    let title: String
    let value: Decimal
    let currencyCode: String
    let icon: String
    let color: Color
    var compact = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(compact ? .body : .title3)
                .foregroundStyle(color)
                .frame(width: compact ? 35 : 42, height: compact ? 35 : 42)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(DisplayFormat.currency(value, code: currencyCode))
                    .font(compact ? .subheadline.bold() : .title3.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            Spacer(minLength: 0)
        }
        .padding(compact ? 13 : 16)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}

private struct ChartLegend: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct ComparisonTransactionsView: View {
    @EnvironmentObject private var store: LedgerStore
    let interval: DateInterval
    var body: some View {
        List {
            Section("Income") { rows(for: .income) }
            Section("Expenses") { rows(for: .expense) }
        }
        .navigationTitle("Compared Transactions")
        .navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private func rows(for type: TransactionType) -> some View {
        let items = transactions.filter { $0.type == type }
        if items.isEmpty {
            Text("No \(type.title.lowercased()) transactions.").foregroundStyle(.secondary)
        } else {
            ForEach(items) { TransactionRow(transaction: $0) }
            LabeledContent("Total", value: DisplayFormat.currency(items.reduce(0) { $0 + $1.amount }, code: store.currencyCode))
        }
    }
    private var transactions: [LedgerTransaction] {
        store.transactions.filter {
            interval.contains($0.date) && ($0.type == .income || $0.type == .expense) &&
            store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
        }.sorted { $0.date > $1.date }
    }
}

private struct AccountReportTransactionsView: View {
    @EnvironmentObject private var store: LedgerStore
    let interval: DateInterval
    let accountIDs: Set<UUID>
    @State private var selectedTransaction: LedgerTransaction?

    var body: some View {
        List {
            ForEach(transactions) { transaction in
                Button { selectedTransaction = transaction } label: {
                    TransactionRow(transaction: transaction)
                }.buttonStyle(.plain)
            }
            Section {
                LabeledContent("Income Total", value: formatted(total(.income)))
                LabeledContent("Expense Total", value: formatted(total(.expense)))
                LabeledContent("Transactions", value: "\(transactions.count)")
            }
        }
        .navigationTitle("Account Transactions")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedTransaction) {
            TransactionSnapshotView(transaction: $0).environmentObject(store)
        }
    }
    private var transactions: [LedgerTransaction] {
        store.transactions.filter {
            interval.contains($0.date) && accountIDs.contains($0.accountID ?? LedgerAccount.legacyMainID) &&
            ($0.type == .income || $0.type == .expense)
        }.sorted { $0.date > $1.date }
    }
    private func total(_ type: TransactionType) -> Decimal {
        transactions.filter { $0.type == type }.reduce(0) { $0 + $1.amount }
    }
    private func formatted(_ amount: Decimal) -> String {
        DisplayFormat.currency(amount, code: store.currencyCode)
    }
}
