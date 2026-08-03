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
            f"Expected one match in {relative}, found {count}: {old[:220]!r}"
        )
    write(relative, text.replace(old, new, 1))


reports = "DailyLedger/Views/ReportsView.swift"

# Make each Receivable Collected summary card open its matching transactions.
replace_once(
    reports,
    r'''            if !receivableMovements.isEmpty {
                ForEach(receivableMovements) { movement in
                    formulaOperator("+", color: color)
                    movementCard(
                        title: "Receivable Collected",
                        movement: movement,
                        icon: "person.crop.circle.badge.checkmark",
                        color: AppTheme.blue
                    )
                }
            }
''',
    r'''            if !receivableMovements.isEmpty {
                ForEach(receivableMovements) { movement in
                    formulaOperator("+", color: color)
                    NavigationLink {
                        ReceivableCollectionTransactionsView(
                            interval: selectedInterval,
                            currencyCode: movement.currencyCode
                        )
                    } label: {
                        movementCard(
                            title: "Receivable Collected",
                            movement: movement,
                            icon: "person.crop.circle.badge.checkmark",
                            color: AppTheme.blue
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
''',
)

# Add a dedicated transaction drill-down. It displays the receivable component,
# not the full transfer, when a receipt crosses zero into Loan Increase.
text = read(reports)
marker = "private struct ReceivableCollectionTransactionsView: View"
if marker in text:
    raise RuntimeError("Receivable collection drill-down already exists")

text += r'''

private struct ReceivableCollectionTransactionsView: View {
    @EnvironmentObject private var store: LedgerStore

    let interval: DateInterval
    let currencyCode: String

    var body: some View {
        List {
            if transactions.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No receivable collections")
                            .font(.headline)
                        Text("No matching receivable collection transactions were found for this period and currency.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                Section {
                    ForEach(transactions) { transaction in
                        receivableCollectionRow(transaction)
                    }
                } header: {
                    HStack {
                        Text("Transactions")
                        Spacer()
                        Text("\(transactions.count)")
                            .font(.caption.bold())
                    }
                } footer: {
                    Text("Amounts show only the receivable collected portion. Any excess that crossed zero remains under Loan Increase.")
                }

                Section {
                    LabeledContent(
                        "Total Receivable Collected",
                        value: DisplayFormat.currency(totalCollected, code: currencyCode)
                    )
                    .font(.subheadline.bold())
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Receivable Collected")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var transactions: [LedgerTransaction] {
        store.transactions.filter { transaction in
            guard interval.contains(transaction.date),
                  store.receivableCollectionAmount(transaction) > 0,
                  let source = store.account(withID: transaction.accountID) else {
                return false
            }
            return source.currencyCode.caseInsensitiveCompare(currencyCode) == .orderedSame
        }.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.createdAt > $1.createdAt
        }
    }

    private var totalCollected: Decimal {
        transactions.reduce(Decimal.zero) {
            $0 + store.receivableCollectionAmount($1)
        }
    }

    private func receivableCollectionRow(_ transaction: LedgerTransaction) -> some View {
        let source = store.account(withID: transaction.accountID)
        let destination = store.account(withID: transaction.destinationAccountID)
        let collected = store.receivableCollectionAmount(transaction)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(source?.name ?? "Receivable Account")
                        .font(.body.weight(.semibold))
                    Text("Received into \(destination?.name ?? "Bank Account")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(DisplayFormat.currency(collected, code: source?.currencyCode ?? currencyCode))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(AppTheme.blue)
                    .multilineTextAlignment(.trailing)
            }

            if !transaction.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(transaction.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 5) {
                Image(systemName: "calendar")
                Text(transaction.date, style: .date)
                Text("•")
                Text(transaction.date, style: .time)
                Spacer()
                if collected < transaction.amount {
                    Text("Partial of \(DisplayFormat.currency(transaction.amount, code: source?.currencyCode ?? currencyCode))")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
'''

write(reports, text)
print("Added Receivable Collected summary-card transaction drill-down.")
