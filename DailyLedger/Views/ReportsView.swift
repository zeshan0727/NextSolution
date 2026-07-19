import Charts
import SwiftUI

private enum ReportPeriod: String, CaseIterable, Identifiable {
    case month = "Monthly"
    case year = "Yearly"
    var id: String { rawValue }
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
    @EnvironmentObject private var store: LedgerStore
    @State private var period: ReportPeriod = .month
    @State private var anchorDate = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    Picker("Report period", selection: $period) {
                        ForEach(ReportPeriod.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)

                    periodNavigator
                    totalCards
                    activityChart
                    categoryBreakdown
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(AppTheme.page)
            .navigationTitle("Reports")
            .onChange(of: period) { _ in anchorDate = Date() }
        }
    }

    private var periodNavigator: some View {
        HStack {
            Button { movePeriod(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 40, height: 40)
                    .background(.background, in: Circle())
            }
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
            .disabled(isCurrentPeriod)
            .opacity(isCurrentPeriod ? 0.35 : 1)
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
                ReportTotalCard(
                    title: "Income",
                    value: totals.income,
                    currencyCode: store.currencyCode,
                    icon: "arrow.down.left.circle.fill",
                    color: AppTheme.green,
                    compact: true
                )
                ReportTotalCard(
                    title: "Expenses",
                    value: totals.expense,
                    currencyCode: store.currencyCode,
                    icon: "arrow.up.right.circle.fill",
                    color: AppTheme.red,
                    compact: true
                )
            }
            ReportTotalCard(
                title: "Loans Paid",
                value: totals.loan,
                currencyCode: store.currencyCode,
                icon: "banknote.fill",
                color: AppTheme.orange
            )
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
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var selectedInterval: DateInterval {
        let component: Calendar.Component = period == .month ? .month : .year
        return Calendar.current.dateInterval(of: component, for: anchorDate)
            ?? DateInterval(start: anchorDate, duration: 1)
    }

    private var selectedTransactions: [LedgerTransaction] {
        store.transactions.filter {
            selectedInterval.contains($0.date) &&
                $0.type != .transfer &&
                store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
        }
    }

    private var totals: LedgerTotals {
        store.totals(in: selectedInterval)
    }

    private var periodTitle: String {
        period == .month
            ? DisplayFormat.monthYear.string(from: anchorDate)
            : DisplayFormat.year.string(from: anchorDate)
    }

    private var isCurrentPeriod: Bool {
        let calendar = Calendar.current
        if period == .month {
            return calendar.isDate(anchorDate, equalTo: Date(), toGranularity: .month)
        }
        return calendar.isDate(anchorDate, equalTo: Date(), toGranularity: .year)
    }

    private var buckets: [ReportBucket] {
        let calendar = Calendar.current
        if period == .month {
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
        let expenses = selectedTransactions.filter { $0.type == .expense && !$0.isLoanPayment }
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
        guard !(direction > 0 && isCurrentPeriod) else { return }
        let component: Calendar.Component = period == .month ? .month : .year
        anchorDate = Calendar.current.date(byAdding: component, value: direction, to: anchorDate) ?? anchorDate
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
