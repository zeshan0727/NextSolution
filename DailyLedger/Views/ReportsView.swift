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
    @State private var unit: Calendar.Component = .month
    @State private var type: TransactionType = .expense

    var body: some View {
        List {
            Picker("Compare", selection: $type) {
                Text("Expenses").tag(TransactionType.expense)
                Text("Income").tag(TransactionType.income)
            }.pickerStyle(.segmented)
            Picker("Period", selection: $unit) {
                Text("Daily").tag(Calendar.Component.day)
                Text("Monthly").tag(Calendar.Component.month)
                Text("Yearly").tag(Calendar.Component.year)
            }.pickerStyle(.segmented)
            Section("Current vs Previous") {
                comparisonRow("Current", interval: currentInterval)
                comparisonRow("Previous", interval: previousInterval)
                LabeledContent("Change", value: DisplayFormat.currency(currentAmount - previousAmount, code: store.currencyCode))
            }
        }
        .navigationTitle("Compare Reports")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var currentInterval: DateInterval { Calendar.current.dateInterval(of: unit, for: Date())! }
    private var previousInterval: DateInterval {
        let date = Calendar.current.date(byAdding: unit, value: -1, to: Date())!
        return Calendar.current.dateInterval(of: unit, for: date)!
    }
    private var currentAmount: Decimal { amount(in: currentInterval) }
    private var previousAmount: Decimal { amount(in: previousInterval) }
    private func amount(in interval: DateInterval) -> Decimal {
        store.transactions.lazy.filter {
            $0.type == type && interval.contains($0.date) && store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
        }.reduce(Decimal.zero) { $0 + $1.amount }
    }
    private func comparisonRow(_ title: String, interval: DateInterval) -> some View {
        NavigationLink {
            PeriodTransactionsView(
                kind: type == .income ? .income : .expenses,
                interval: interval
            )
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text("\(transactionCount(in: interval)) transactions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(DisplayFormat.currency(amount(in: interval), code: store.currencyCode))
                    .font(.subheadline.bold())
            }
        }
    }
    private func transactionCount(in interval: DateInterval) -> Int {
        store.transactions.lazy.filter {
            $0.type == type && interval.contains($0.date) &&
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
                    if kind == .summary || kind == .income || kind == .expenses {
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
