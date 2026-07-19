import SwiftUI

struct BalanceCard: View {
    let balance: Decimal
    let income: Decimal
    let expense: Decimal
    let loan: Decimal
    let currencyCode: String
    let accountSummary: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("REMAINING ACCOUNT BALANCE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Text(DisplayFormat.currency(balance, code: currencyCode))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                Text(accountSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }

            HStack(spacing: 16) {
                BalanceMiniStat(
                    title: "Income",
                    value: income,
                    icon: "arrow.down.left",
                    currencyCode: currencyCode
                )
                BalanceMiniStat(
                    title: "Expenses",
                    value: expense,
                    icon: "arrow.up.right",
                    currencyCode: currencyCode
                )
                BalanceMiniStat(
                    title: "Loans paid",
                    value: loan,
                    icon: "banknote.fill",
                    currencyCode: currencyCode
                )
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.balanceGradient)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.10))
                .frame(width: 140, height: 140)
                .offset(x: 45, y: -55)
        }
        .shadow(color: AppTheme.purple.opacity(0.22), radius: 18, y: 10)
        .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }
}

private struct BalanceMiniStat: View {
    let title: String
    let value: Decimal
    let icon: String
    let currencyCode: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.caption.bold())
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                Text(DisplayFormat.currency(value, code: currencyCode))
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TransactionRow: View {
    @EnvironmentObject private var store: LedgerStore
    let transaction: LedgerTransaction

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: AppTheme.categoryIcon(transaction.category))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.categoryColor(transaction.category))
                .frame(width: 42, height: 42)
                .background(
                    AppTheme.categoryColor(transaction.category).opacity(0.13),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(primaryText)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(secondaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText)
                    .font(.subheadline.bold())
                    .foregroundStyle(amountColor)
                if transaction.type == .transfer,
                   let destination = destinationAccount,
                   destination.currencyCode != sourceAccount?.currencyCode {
                    Text("+" + DisplayFormat.currency(
                        transaction.destinationAmount ?? transaction.amount,
                        code: destination.currencyCode
                    ))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.blue)
                }
                if let runningBalance = store.runningBalances[transaction.id] {
                    Text("Balance " + DisplayFormat.currency(
                        runningBalance,
                        code: sourceAccount?.currencyCode ?? store.currencyCode
                    ))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.65)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private var amountText: String {
        let prefix = transaction.type == .income ? "+" : "−"
        return prefix + DisplayFormat.currency(
            transaction.amount,
            code: sourceAccount?.currencyCode ?? store.currencyCode
        )
    }

    private var primaryText: String {
        if transaction.type == .transfer {
            return "\(sourceAccount?.name ?? "Account") → \(destinationAccount?.name ?? "Account")"
        }
        if let vendor = transaction.vendor, !vendor.isEmpty { return vendor }
        return transaction.category
    }

    private var secondaryText: String {
        if transaction.type == .transfer {
            return transaction.details.isEmpty ? "Transfer" : transaction.details
        }
        return [sourceAccount?.name, transaction.category]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var sourceAccount: LedgerAccount? {
        store.account(withID: transaction.accountID)
    }

    private var destinationAccount: LedgerAccount? {
        store.account(withID: transaction.destinationAccountID)
    }

    private var amountColor: Color {
        switch transaction.type {
        case .income: return AppTheme.green
        case .expense: return AppTheme.red
        case .transfer: return AppTheme.purple
        }
    }
}

struct EmptyLedgerView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.fill")
                .font(.system(size: 34))
                .foregroundStyle(AppTheme.purple.opacity(0.7))
                .frame(width: 72, height: 72)
                .background(AppTheme.purple.opacity(0.10), in: Circle())
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(36)
    }
}
