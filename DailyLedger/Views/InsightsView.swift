import SwiftUI

private struct SpendingSuggestion: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let color: Color
}

struct InsightsView: View {
    @EnvironmentObject private var store: LedgerStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This Month")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(DisplayFormat.currency(currentExpense, code: store.currencyCode))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        Text(monthComparisonText)
                            .font(.subheadline)
                            .foregroundStyle(monthChange > 0 ? AppTheme.red : AppTheme.green)
                    }
                    .padding(.vertical, 8)
                }

                Section("Suggestions to Cut Expenses") {
                    if suggestions.isEmpty {
                        Text("Add more expenses this month to receive useful suggestions.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(suggestions) { suggestion in
                            HStack(alignment: .top, spacing: 13) {
                                Image(systemName: suggestion.icon)
                                    .foregroundStyle(suggestion.color)
                                    .frame(width: 36, height: 36)
                                    .background(suggestion.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(suggestion.title).font(.headline)
                                    Text(suggestion.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                }

                Section {
                    Text("Insights are calculated privately on this iPhone. No financial data is sent to an external AI service.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("AI Insights")
            .listStyle(.insetGrouped)
        }
    }

    private var currentMonth: DateInterval {
        Calendar.current.dateInterval(of: .month, for: Date())!
    }

    private var previousMonth: DateInterval {
        let date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        return Calendar.current.dateInterval(of: .month, for: date)!
    }

    private var currentExpenses: [LedgerTransaction] {
        expenses(in: currentMonth)
    }

    private var currentExpense: Decimal {
        currentExpenses.reduce(0) { $0 + $1.amount }
    }

    private var previousExpense: Decimal {
        expenses(in: previousMonth).reduce(0) { $0 + $1.amount }
    }

    private var monthChange: Decimal { currentExpense - previousExpense }

    private var monthComparisonText: String {
        if previousExpense == 0 { return "No previous-month comparison yet" }
        let direction = monthChange > 0 ? "more" : "less"
        return "\(DisplayFormat.currency(abs(monthChange), code: store.currencyCode)) \(direction) than last month"
    }

    private var suggestions: [SpendingSuggestion] {
        guard currentExpense > 0 else { return [] }
        var result: [SpendingSuggestion] = []
        let grouped = Dictionary(grouping: currentExpenses, by: \.category)
        if let top = grouped.max(by: { left, right in
            expenseTotal(left.value) < expenseTotal(right.value)
        }) {
            let amount = top.value.reduce(Decimal.zero) { $0 + $1.amount }
            let target = amount / 10
            result.append(SpendingSuggestion(
                id: "top-category",
                title: "Reduce \(top.key) by 10%",
                detail: "Your largest category is \(DisplayFormat.currency(amount, code: store.currencyCode)). A 10% reduction could save \(DisplayFormat.currency(target, code: store.currencyCode)) this month.",
                icon: "chart.pie.fill",
                color: AppTheme.orange
            ))
        }
        let small = currentExpenses.filter { $0.amount <= 50 }
        if small.count >= 5 {
            let total = small.reduce(Decimal.zero) { $0 + $1.amount }
            result.append(SpendingSuggestion(
                id: "small-purchases",
                title: "Watch frequent small purchases",
                detail: "\(small.count) purchases of \(store.currencyCode) 50 or less total \(DisplayFormat.currency(total, code: store.currencyCode)). Combining or skipping a few can make a visible difference.",
                icon: "cup.and.saucer.fill",
                color: AppTheme.purple
            ))
        }
        if monthChange > 0, previousExpense > 0 {
            result.append(SpendingSuggestion(
                id: "month-growth",
                title: "Spending is above last month",
                detail: "You have spent \(DisplayFormat.currency(monthChange, code: store.currencyCode)) more. Review the top category before making non-essential purchases.",
                icon: "arrow.up.right.circle.fill",
                color: AppTheme.red
            ))
        }
        return result
    }

    private func expenses(in interval: DateInterval) -> [LedgerTransaction] {
        store.transactions.filter {
            $0.type == .expense && interval.contains($0.date) &&
            store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
        }
    }

    private func expenseTotal(_ transactions: [LedgerTransaction]) -> Decimal {
        transactions.reduce(Decimal.zero) { $0 + $1.amount }
    }
}
