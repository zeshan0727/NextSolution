import Charts
import SwiftUI

private enum RecoveredComparePeriod: String, CaseIterable, Identifiable {
    case day = "Daily"
    case month = "Monthly"
    case year = "Yearly"

    var id: String { rawValue }
}

private enum RecoveredCompareMetric: String, CaseIterable, Identifiable {
    case income = "Income"
    case expenses = "Expenses"
    case net = "Net Result"

    var id: String { rawValue }
    var color: Color {
        switch self {
        case .income: return AppTheme.green
        case .expenses: return AppTheme.red
        case .net: return AppTheme.purple
        }
    }
}

private struct RecoveredComparisonBar: Identifiable {
    let id: String
    let title: String
    let value: Double
}

struct ReportsV124View: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        CompareReportsV124View()
                    } label: {
                        recoveredReportRow(
                            title: "Compare Reports",
                            subtitle: "Compare daily, monthly, or yearly income and expenses",
                            icon: "chart.bar.xaxis.ascending",
                            color: AppTheme.purple
                        )
                    }

                    NavigationLink {
                        BudgetPlannerV124View()
                    } label: {
                        recoveredReportRow(
                            title: "Budget Planner",
                            subtitle: "Set a monthly budget and track actual spending",
                            icon: "target",
                            color: AppTheme.orange
                        )
                    }
                } header: {
                    Text("Planning & comparison")
                }

                Section {
                    NavigationLink {
                        ReportsView()
                    } label: {
                        recoveredReportRow(
                            title: "Detailed Reports",
                            subtitle: "Financial summary, income, expenses, transfers, and categories",
                            icon: "doc.text.magnifyingglass",
                            color: AppTheme.blue
                        )
                    }
                } header: {
                    Text("Detailed reporting")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Reports")
        }
    }

    private func recoveredReportRow(
        title: String,
        subtitle: String,
        icon: String,
        color: Color
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 5)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
        }
    }
}

private struct CompareReportsV124View: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var period = RecoveredComparePeriod.month
    @State private var metric = RecoveredCompareMetric.expenses
    @State private var anchorDate = Date()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                Picker("Period", selection: $period) {
                    ForEach(RecoveredComparePeriod.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Metric", selection: $metric) {
                    ForEach(RecoveredCompareMetric.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                periodNavigator
                comparisonCards
                comparisonChart
                changeSummary
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(AppTheme.page)
        .navigationTitle("Compare Reports")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var periodNavigator: some View {
        HStack {
            Button {
                moveAnchor(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 42, height: 42)
                    .recoveredSurface(tint: AppTheme.blue, cornerRadius: 21)
            }
            Spacer()
            VStack(spacing: 2) {
                Text(currentTitle)
                    .font(.headline)
                Text("Compared with \(previousTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                moveAnchor(1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 42, height: 42)
                    .recoveredSurface(tint: AppTheme.blue, cornerRadius: 21)
            }
            .disabled(currentInterval.contains(Date()))
            .opacity(currentInterval.contains(Date()) ? 0.35 : 1)
        }
    }

    private var comparisonCards: some View {
        HStack(spacing: 12) {
            comparisonCard(title: "Current", value: currentValue, color: metric.color)
            comparisonCard(title: "Previous", value: previousValue, color: AppTheme.blue)
        }
    }

    private func comparisonCard(title: String, value: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(DisplayFormat.currency(value, code: store.currencyCode))
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text(metric.rawValue)
                .font(.caption)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .recoveredSurface(tint: color)
    }

    private var comparisonChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Side-by-side comparison")
                .font(.headline)

            Chart(comparisonBars) { item in
                BarMark(
                    x: .value("Period", item.title),
                    y: .value(metric.rawValue, item.value)
                )
                .foregroundStyle(by: .value("Period", item.title))
                .cornerRadius(6)
            }
            .chartLegend(.hidden)
            .frame(height: 250)
        }
        .padding(16)
        .recoveredSurface(tint: metric.color)
    }

    private var changeSummary: some View {
        let change = currentValue - previousValue
        let isPositiveForUser = metric == .expenses ? change <= 0 : change >= 0
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: change == 0 ? "equal.circle.fill" : (change > 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill"))
                .font(.title2)
                .foregroundStyle(isPositiveForUser ? AppTheme.green : AppTheme.red)
            VStack(alignment: .leading, spacing: 4) {
                Text(change == 0 ? "No change" : "\(DisplayFormat.currency(abs(change), code: store.currencyCode)) difference")
                    .font(.headline)
                Text(summaryText(change: change))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .recoveredSurface(tint: isPositiveForUser ? AppTheme.green : AppTheme.red)
    }

    private var comparisonBars: [RecoveredComparisonBar] {
        [
            RecoveredComparisonBar(
                id: "previous",
                title: "Previous",
                value: NSDecimalNumber(decimal: previousValue).doubleValue
            ),
            RecoveredComparisonBar(
                id: "current",
                title: "Current",
                value: NSDecimalNumber(decimal: currentValue).doubleValue
            )
        ]
    }

    private var currentTotals: LedgerTotals { store.totals(in: currentInterval) }
    private var previousTotals: LedgerTotals { store.totals(in: previousInterval) }

    private var currentValue: Decimal { value(from: currentTotals) }
    private var previousValue: Decimal { value(from: previousTotals) }

    private func value(from totals: LedgerTotals) -> Decimal {
        switch metric {
        case .income: return totals.income
        case .expenses: return totals.expense
        case .net: return totals.income - totals.expense
        }
    }

    private var currentInterval: DateInterval {
        interval(containing: anchorDate)
    }

    private var previousInterval: DateInterval {
        let date: Date
        switch period {
        case .day:
            date = Calendar.current.date(byAdding: .day, value: -1, to: currentInterval.start) ?? currentInterval.start
        case .month:
            date = Calendar.current.date(byAdding: .month, value: -1, to: currentInterval.start) ?? currentInterval.start
        case .year:
            date = Calendar.current.date(byAdding: .year, value: -1, to: currentInterval.start) ?? currentInterval.start
        }
        return interval(containing: date)
    }

    private func interval(containing date: Date) -> DateInterval {
        let calendar = Calendar.current
        switch period {
        case .day:
            return calendar.dateInterval(of: .day, for: date)!
        case .month:
            return calendar.dateInterval(of: .month, for: date)!
        case .year:
            return calendar.dateInterval(of: .year, for: date)!
        }
    }

    private var currentTitle: String { title(for: currentInterval.start) }
    private var previousTitle: String { title(for: previousInterval.start) }

    private func title(for date: Date) -> String {
        switch period {
        case .day: return DisplayFormat.day.string(from: date)
        case .month: return DisplayFormat.monthYear.string(from: date)
        case .year: return DisplayFormat.year.string(from: date)
        }
    }

    private func moveAnchor(_ direction: Int) {
        let component: Calendar.Component
        switch period {
        case .day: component = .day
        case .month: component = .month
        case .year: component = .year
        }
        anchorDate = Calendar.current.date(byAdding: component, value: direction, to: anchorDate) ?? anchorDate
    }

    private func summaryText(change: Decimal) -> String {
        guard change != 0 else { return "The selected metric matches the previous period." }
        let direction = change > 0 ? "higher" : "lower"
        return "\(metric.rawValue) is \(direction) than \(previousTitle)."
    }
}

private struct BudgetPlannerV124View: View {
    @EnvironmentObject private var store: LedgerStore
    @AppStorage("DailyLedgerMonthlyBudgetV124") private var monthlyBudget = 0.0

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                budgetInput
                budgetStatus
                categoryPlan
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(AppTheme.page)
        .navigationTitle("Budget Planner")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var budgetInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Monthly spending budget", systemImage: "target")
                .font(.headline)
            TextField("Enter budget", value: $monthlyBudget, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .font(.title2.bold())
                .padding(13)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            Text("This value is stored locally and can be changed at any time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .recoveredSurface(tint: AppTheme.orange)
    }

    private var budgetStatus: some View {
        let budget = Decimal(monthlyBudget)
        let remaining = budget - currentMonthExpense
        let ratio = monthlyBudget > 0
            ? min(max(NSDecimalNumber(decimal: currentMonthExpense).doubleValue / monthlyBudget, 0), 1)
            : 0

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Spent this month")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(DisplayFormat.currency(currentMonthExpense, code: store.currencyCode))
                        .font(.title2.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(remaining >= 0 ? "Remaining" : "Over budget")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(DisplayFormat.currency(abs(remaining), code: store.currencyCode))
                        .font(.headline)
                        .foregroundStyle(remaining >= 0 ? AppTheme.green : AppTheme.red)
                }
            }
            ProgressView(value: ratio)
                .tint(ratio >= 1 ? AppTheme.red : AppTheme.green)
            Text(monthlyBudget > 0 ? "\(Int(ratio * 100))% of the monthly budget used" : "Enter a monthly budget to start tracking progress")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .recoveredSurface(tint: remaining >= 0 ? AppTheme.green : AppTheme.red)
    }

    private var categoryPlan: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Category spending")
                .font(.headline)

            if categoryTotals.isEmpty {
                Text("Expense categories will appear after transactions are recorded this month.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            } else {
                ForEach(categoryTotals, id: \.name) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(item.name, systemImage: AppTheme.categoryIcon(item.name))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(DisplayFormat.currency(item.amount, code: store.currencyCode))
                                .font(.subheadline.bold())
                        }
                        ProgressView(value: categoryRatio(item.amount))
                            .tint(AppTheme.categoryColor(item.name))
                    }
                }
            }
        }
        .padding(16)
        .recoveredSurface(tint: AppTheme.purple)
    }

    private var currentMonth: DateInterval {
        Calendar.current.dateInterval(of: .month, for: Date())!
    }

    private var currentMonthExpenses: [LedgerTransaction] {
        store.transactions.filter {
            $0.type == .expense &&
            currentMonth.contains($0.date) &&
            (store.account(withID: $0.accountID)?.currencyCode ?? store.currencyCode) == store.currencyCode
        }
    }

    private var currentMonthExpense: Decimal {
        currentMonthExpenses.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var categoryTotals: [(name: String, amount: Decimal)] {
        Dictionary(grouping: currentMonthExpenses, by: \.category)
            .map { key, value in
                (key, value.reduce(Decimal.zero) { $0 + $1.amount })
            }
            .sorted { $0.1 > $1.1 }
            .prefix(8)
            .map { $0 }
    }

    private func categoryRatio(_ amount: Decimal) -> Double {
        guard currentMonthExpense > 0 else { return 0 }
        return min(
            NSDecimalNumber(decimal: amount).doubleValue /
            NSDecimalNumber(decimal: currentMonthExpense).doubleValue,
            1
        )
    }
}
