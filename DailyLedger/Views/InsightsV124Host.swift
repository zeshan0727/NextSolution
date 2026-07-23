import SwiftUI

struct InsightsV124Host: View {
    @EnvironmentObject private var store: LedgerStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: insight.icon)
                    .font(.title3)
                    .foregroundStyle(insight.color)
                    .frame(width: 40, height: 40)
                    .background(insight.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Today's Ledger Insight")
                            .font(.headline)
                        Spacer()
                        Text("Rotates daily")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(insight.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(AppTheme.page)

            Divider()
            InsightsView()
        }
    }

    private var insight: (message: String, icon: String, color: Color) {
        let options = insightOptions
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return options[day % max(options.count, 1)]
    }

    private var insightOptions: [(message: String, icon: String, color: Color)] {
        var options: [(String, String, Color)] = []
        let expenses = currentMonthExpenses
        let total = expenses.reduce(Decimal.zero) { $0 + $1.amount }

        if let highest = Dictionary(grouping: expenses, by: \.category)
            .map({ key, value in (key, value.reduce(Decimal.zero) { $0 + $1.amount }) })
            .max(by: { $0.1 < $1.1 }) {
            options.append((
                "\(highest.0) is your largest category this month at \(DisplayFormat.currency(highest.1, code: store.currencyCode)).",
                "chart.pie.fill",
                AppTheme.orange
            ))
        }

        let elapsedDays = max(Calendar.current.component(.day, from: Date()), 1)
        let dailyAverage = total / Decimal(elapsedDays)
        options.append((
            "Your current daily spending average is \(DisplayFormat.currency(dailyAverage, code: store.currencyCode)).",
            "speedometer",
            AppTheme.teal
        ))

        let smallPurchases = expenses.filter { $0.amount <= 50 }
        if smallPurchases.count >= 3 {
            let amount = smallPurchases.reduce(Decimal.zero) { $0 + $1.amount }
            options.append((
                "\(smallPurchases.count) purchases of \(store.currencyCode) 50 or less total \(DisplayFormat.currency(amount, code: store.currencyCode)).",
                "cup.and.saucer.fill",
                AppTheme.purple
            ))
        }

        let previousTotal = previousMonthExpenses.reduce(Decimal.zero) { $0 + $1.amount }
        if previousTotal > 0 {
            let difference = total - previousTotal
            options.append((
                difference > 0
                    ? "Spending is \(DisplayFormat.currency(difference, code: store.currencyCode)) above last month so far."
                    : "Spending is \(DisplayFormat.currency(abs(difference), code: store.currencyCode)) below last month so far.",
                difference > 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill",
                difference > 0 ? AppTheme.red : AppTheme.green
            ))
        }

        if options.isEmpty {
            options.append((
                "Record a few expenses to unlock personalized spending insights.",
                "sparkles",
                AppTheme.blue
            ))
        }

        return options
    }

    private var currentMonthExpenses: [LedgerTransaction] {
        expenses(in: Calendar.current.dateInterval(of: .month, for: Date())!)
    }

    private var previousMonthExpenses: [LedgerTransaction] {
        let previous = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        return expenses(in: Calendar.current.dateInterval(of: .month, for: previous)!)
    }

    private func expenses(in interval: DateInterval) -> [LedgerTransaction] {
        store.transactions.filter {
            $0.type == .expense &&
            interval.contains($0.date) &&
            (store.account(withID: $0.accountID)?.currencyCode ?? store.currencyCode) == store.currencyCode
        }
    }
}
