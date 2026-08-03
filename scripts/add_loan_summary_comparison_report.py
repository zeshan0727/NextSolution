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
        raise RuntimeError(
            f"Expected one match in {relative}, found {count}: {old[:240]!r}"
        )
    write(relative, text.replace(old, new, 1))


reports = "DailyLedger/Views/ReportsView.swift"

# Add the report to the Planning & Comparison section.
replace_once(
    reports,
    '''                    NavigationLink { LoanMovementReportView() } label: {
                        Label("Loan Movement by Currency", systemImage: "banknote.fill")
                    }
                    NavigationLink { AccountNatureReportView() } label: {
''',
    '''                    NavigationLink { LoanMovementReportView() } label: {
                        Label("Loan Movement by Currency", systemImage: "banknote.fill")
                    }
                    NavigationLink { LoanSummaryComparisonView() } label: {
                        Label("Loan Summary Comparison", systemImage: "chart.bar.doc.horizontal.fill")
                    }
                    NavigationLink { AccountNatureReportView() } label: {
''',
)

# Append a monthly comparison report. Every source currency remains visible in
# its own section. Only the consolidated Net Movement is converted into the
# app's single reporting currency using the fixed report conversion rates.
text = read(reports)
marker = "private struct LoanSummaryComparisonView: View"
if marker in text:
    raise RuntimeError("Loan Summary Comparison report already exists")

text += r'''

private struct LoanSummaryComparisonView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var selectedMonth = Date()

    var body: some View {
        List {
            Section("Comparison Period") {
                DatePicker(
                    "Selected Month",
                    selection: $selectedMonth,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)

                LabeledContent("Selected", value: monthTitle(currentInterval.start))
                LabeledContent("Previous", value: monthTitle(previousInterval.start))
            }

            Section {
                consolidatedRow(
                    title: monthTitle(currentInterval.start),
                    amount: consolidatedNetMovement(in: currentInterval)
                )
                consolidatedRow(
                    title: monthTitle(previousInterval.start),
                    amount: consolidatedNetMovement(in: previousInterval)
                )
                consolidatedRow(
                    title: "Change",
                    amount: consolidatedNetMovement(in: currentInterval) -
                        consolidatedNetMovement(in: previousInterval)
                )
            } header: {
                Text("Consolidated Net Movement — \(store.currencyCode.uppercased())")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Only this consolidated section is converted. Currency sections below remain in their original currencies.")
                    Text("Conversion uses the fixed report rates configured in Next Ledger.")
                    if !unsupportedCurrencies.isEmpty {
                        Text("No fixed conversion rate: \(unsupportedCurrencies.joined(separator: ", ")). These currencies remain visible below but are excluded from the consolidated total.")
                            .foregroundStyle(AppTheme.orange)
                    }
                }
            }

            ForEach(currencies, id: \.self) { currency in
                Section {
                    comparisonHeader
                    comparisonRow(
                        "Loan Increase",
                        current: loanIncrease(currency: currency, in: currentInterval),
                        previous: loanIncrease(currency: currency, in: previousInterval),
                        currency: currency
                    )
                    comparisonRow(
                        "Loan Payments",
                        current: loanPayments(currency: currency, in: currentInterval),
                        previous: loanPayments(currency: currency, in: previousInterval),
                        currency: currency
                    )
                    comparisonRow(
                        "Net Movement",
                        current: netMovement(currency: currency, in: currentInterval),
                        previous: netMovement(currency: currency, in: previousInterval),
                        currency: currency
                    )
                } header: {
                    HStack {
                        Text(currency)
                        Spacer()
                        Text("Original Currency")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Loan Summary Comparison")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var currentInterval: DateInterval {
        Calendar.current.dateInterval(of: .month, for: selectedMonth)!
    }

    private var previousInterval: DateInterval {
        let previousDate = Calendar.current.date(
            byAdding: .month,
            value: -1,
            to: currentInterval.start
        ) ?? currentInterval.start
        return Calendar.current.dateInterval(of: .month, for: previousDate)!
    }

    private var loanAccounts: [LedgerAccount] {
        store.accounts.filter {
            $0.group == .payments || $0.nature == .loan
        }
    }

    private var currencies: [String] {
        let values = Set(loanAccounts.map { $0.currencyCode.uppercased() })
        return values.isEmpty ? [store.currencyCode.uppercased()] : values.sorted()
    }

    private var unsupportedCurrencies: [String] {
        currencies.filter { conversionRate(from: $0) == nil }
    }

    private var comparisonHeader: some View {
        HStack(spacing: 8) {
            Text("Metric")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Selected")
                .frame(width: 92, alignment: .trailing)
            Text("Previous")
                .frame(width: 92, alignment: .trailing)
        }
        .font(.caption2.bold())
        .foregroundStyle(.secondary)
    }

    private func comparisonRow(
        _ title: String,
        current: Decimal,
        previous: Decimal,
        currency: String
    ) -> some View {
        let change = current - previous
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(title == "Net Movement" ? .bold : .regular))
                Text("Change: \(DisplayFormat.currency(change, code: currency))")
                    .font(.caption2)
                    .foregroundStyle(change >= 0 ? AppTheme.green : AppTheme.red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(DisplayFormat.currency(current, code: currency))
                .font(.caption.bold().monospacedDigit())
                .frame(width: 92, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.45)

            Text(DisplayFormat.currency(previous, code: currency))
                .font(.caption.bold().monospacedDigit())
                .frame(width: 92, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
        }
        .padding(.vertical, 2)
    }

    private func consolidatedRow(title: String, amount: Decimal) -> some View {
        LabeledContent {
            Text(title)
                .font(.subheadline.weight(title == "Change" ? .bold : .regular))
        } value: {
            Text(DisplayFormat.currency(amount, code: store.currencyCode))
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(amount >= 0 ? AppTheme.green : AppTheme.red)
        }
    }

    private func loanIncrease(currency: String, in interval: DateInterval) -> Decimal {
        store.transactions.reduce(Decimal.zero) { total, transaction in
            guard interval.contains(transaction.date),
                  let source = store.account(withID: transaction.accountID),
                  source.currencyCode.caseInsensitiveCompare(currency) == .orderedSame else {
                return total
            }

            if source.group == .payments,
               transaction.type == .expense || transaction.type == .transfer {
                return total + paymentLoanIncreasePortion(transaction, sourceID: source.id)
            }

            if source.group != .payments,
               source.nature == .loan,
               transaction.type == .expense || transaction.type == .transfer {
                return total + transaction.amount
            }

            return total
        }
    }

    private func loanPayments(currency: String, in interval: DateInterval) -> Decimal {
        store.transactions.reduce(Decimal.zero) { total, transaction in
            guard interval.contains(transaction.date),
                  transaction.type == .transfer,
                  let destination = store.account(withID: transaction.destinationAccountID),
                  destination.currencyCode.caseInsensitiveCompare(currency) == .orderedSame else {
                return total
            }

            let destinationAmount = transaction.destinationAmount ?? transaction.amount

            if destination.group == .payments {
                return total + paymentLoanPaymentPortion(
                    transaction,
                    destinationID: destination.id,
                    destinationAmount: destinationAmount
                )
            }

            if destination.group != .payments, destination.nature == .loan {
                return total + destinationAmount
            }

            return total
        }
    }

    private func paymentLoanIncreasePortion(
        _ transaction: LedgerTransaction,
        sourceID: UUID
    ) -> Decimal {
        guard let after = store.runningBalance(
            for: transaction.id,
            accountID: sourceID
        ) else {
            return transaction.amount
        }

        let before = after + transaction.amount
        return max(Decimal.zero, transaction.amount - max(Decimal.zero, before))
    }

    private func paymentLoanPaymentPortion(
        _ transaction: LedgerTransaction,
        destinationID: UUID,
        destinationAmount: Decimal
    ) -> Decimal {
        guard let after = store.runningBalance(
            for: transaction.id,
            accountID: destinationID
        ) else {
            return destinationAmount
        }

        let before = after - destinationAmount
        return min(destinationAmount, max(Decimal.zero, -before))
    }

    private func netMovement(currency: String, in interval: DateInterval) -> Decimal {
        loanIncrease(currency: currency, in: interval) -
            loanPayments(currency: currency, in: interval)
    }

    private func consolidatedNetMovement(in interval: DateInterval) -> Decimal {
        currencies.reduce(Decimal.zero) { total, currency in
            guard let rate = conversionRate(from: currency) else { return total }
            return total + netMovement(currency: currency, in: interval) * rate
        }
    }

    private func conversionRate(from currency: String) -> Decimal? {
        if currency.caseInsensitiveCompare(store.currencyCode) == .orderedSame {
            return 1
        }
        return store.fixedReportConversionRate(
            from: currency,
            to: store.currencyCode
        )
    }

    private func monthTitle(_ date: Date) -> String {
        Self.monthFormatter.string(from: date)
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
}
'''

write(reports, text)
print("Added monthly Loan Summary Comparison with original-currency detail and one fixed-rate consolidated Net Movement.")
