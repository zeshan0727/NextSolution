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


def replace_range(relative: str, start_marker: str, end_marker: str, replacement: str) -> None:
    text = read(relative)
    start = text.find(start_marker)
    if start < 0:
        raise RuntimeError(f"Start marker not found in {relative}: {start_marker!r}")
    end = text.find(end_marker, start)
    if end < 0:
        raise RuntimeError(f"End marker not found in {relative}: {end_marker!r}")
    write(relative, text[:start] + replacement + text[end:])


# Keep Receivable and Payable enum values for saved-data compatibility, but do
# not automatically alter an account's native nature. Payments classification is
# driven by the live balance instead.
model = "DailyLedger/Models/LedgerTransaction.swift"
replace_once(
    model,
    '''enum AccountNature: String, Codable, CaseIterable, Identifiable {
    case unassigned
    case loan
    case control
    case asset
    case dailyExpense
    case bank

    var id: String { rawValue }
    var title: String {
        switch self {
        case .unassigned: return "Unassigned"
        case .loan: return "Loan"
        case .control: return "Control"
        case .asset: return "Asset"
        case .dailyExpense: return "Daily Expense"
        case .bank: return "Bank"
        }
    }
}
''',
    '''enum AccountNature: String, Codable, CaseIterable, Identifiable {
    case unassigned
    case loan
    case receivable
    case payable
    case control
    case asset
    case dailyExpense
    case bank

    var id: String { rawValue }
    var title: String {
        switch self {
        case .unassigned: return "Unassigned"
        case .loan: return "Loan"
        case .receivable: return "Receivable"
        case .payable: return "Payable"
        case .control: return "Control"
        case .asset: return "Asset"
        case .dailyExpense: return "Daily Expense"
        case .bank: return "Bank"
        }
    }
}
''',
)


# Accounts tab: Payments is split visually into Receivables and Payables using
# each account's current balance. Positive is receivable; negative is payable.
# At zero, the opening-balance sign is used so a settled account stays on its
# familiar side. Native nature is never changed.
accounts = "DailyLedger/Views/AccountsView.swift"
replace_once(
    accounts,
    "import SwiftUI\n\nstruct AccountsView: View {\n",
    '''import SwiftUI

private enum PaymentBalanceClass: String, CaseIterable, Identifiable {
    case receivable
    case payable

    var id: String { rawValue }
    var pluralTitle: String { self == .receivable ? "Receivables" : "Payables" }
    var icon: String {
        self == .receivable
            ? "arrow.down.left.circle.fill"
            : "arrow.up.right.circle.fill"
    }
}

struct AccountsView: View {
''',
)

replace_range(
    accounts,
    "                ForEach(AccountGroup.allCases) { group in\n",
    "            .listStyle(.insetGrouped)\n",
    '''                ForEach(AccountGroup.allCases) { group in
                    if group == .payments {
                        let receivables = paymentAccounts(.receivable)
                        let payables = paymentAccounts(.payable)
                        if !receivables.isEmpty || !payables.isEmpty {
                            Section {
                                paymentGroupHeader(.receivable, accounts: receivables)
                                if receivables.isEmpty {
                                    Text("No matching receivable accounts.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(receivables) { account in
                                        accountLink(account)
                                    }
                                }

                                paymentGroupHeader(.payable, accounts: payables)
                                if payables.isEmpty {
                                    Text("No matching payable accounts.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(payables) { account in
                                        accountLink(account)
                                    }
                                }
                            } header: {
                                HStack {
                                    Text("PAYMENTS")
                                    Spacer()
                                    Text(groupBalanceText(receivables + payables))
                                        .font(.caption.weight(.semibold))
                                }
                            }
                        }
                    } else {
                        let accounts = accounts(in: group)
                        if !accounts.isEmpty {
                            Section {
                                ForEach(accounts) { account in
                                    accountLink(account)
                                }
                            } header: {
                                HStack {
                                    Text(group.title.uppercased())
                                    Spacer()
                                    Text(groupBalanceText(accounts))
                                        .font(.caption.weight(.semibold))
                                }
                            }
                        }
                    }
                }
            }
''',
)

replace_once(
    accounts,
    '''    private func accounts(in group: AccountGroup) -> [LedgerAccount] {
''',
    '''    @ViewBuilder
    private func accountLink(_ account: LedgerAccount) -> some View {
        NavigationLink {
            AccountDetailView(accountID: account.id)
        } label: {
            AccountRow(
                account: account,
                ownBalance: store.balance(for: account),
                parentName: store.account(withID: account.parentAccountID)?.name,
                consolidatedTotals: store.consolidatedBalances(for: account),
                subAccountCount: store.subAccounts(of: account.id).count
            )
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                editingAccount = account
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(AppTheme.blue)
        }
    }

    private func paymentClass(for account: LedgerAccount) -> PaymentBalanceClass {
        let current = store.balance(for: account)
        if current < 0 { return .payable }
        if current > 0 { return .receivable }
        return account.openingBalance < 0 ? .payable : .receivable
    }

    private func paymentAccounts(_ type: PaymentBalanceClass) -> [LedgerAccount] {
        accounts(in: .payments).filter { paymentClass(for: $0) == type }
    }

    private func paymentGroupHeader(
        _ type: PaymentBalanceClass,
        accounts: [LedgerAccount]
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: type.icon)
                .foregroundStyle(type == .receivable ? AppTheme.green : AppTheme.orange)
                .frame(width: 30, height: 30)
                .background(
                    (type == .receivable ? AppTheme.green : AppTheme.orange).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 9)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(type.pluralTitle)
                    .font(.subheadline.bold())
                Text("\\(accounts.count) account\\(accounts.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(groupBalanceText(accounts))
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.62)
        }
        .padding(.vertical, 5)
        .listRowBackground(
            (type == .receivable ? AppTheme.green : AppTheme.orange).opacity(0.055)
        )
    }

    private func accounts(in group: AccountGroup) -> [LedgerAccount] {
''',
)


# Transaction classification helpers. A Payments -> Bank receipt can be split
# automatically when it crosses zero: first it collects the outstanding
# receivable, and only the excess becomes a loan increase.
store = "DailyLedger/Services/LedgerStore.swift"
replace_once(
    store,
    '''    func isReportIncome(_ transaction: LedgerTransaction) -> Bool {
        transaction.type == .income || isAmaraTransfer(transaction)
    }
''',
    '''    func isReportIncome(_ transaction: LedgerTransaction) -> Bool {
        transaction.type == .income ||
            (isAmaraTransfer(transaction) && !isPaymentToBankTransfer(transaction))
    }
''',
)

replace_once(
    store,
    '''    private func isAmaraTransfer(_ transaction: LedgerTransaction) -> Bool {
''',
    '''    func isBankAccount(_ account: LedgerAccount?) -> Bool {
        guard let account else { return false }
        return account.nature == .bank ||
            account.group == .qatar ||
            account.group == .pakistan
    }

    func isPaymentToBankTransfer(_ transaction: LedgerTransaction) -> Bool {
        guard transaction.type == .transfer,
              let source = account(withID: transaction.accountID),
              source.group == .payments else { return false }
        return isBankAccount(account(withID: transaction.destinationAccountID))
    }

    func isBankToPaymentTransfer(_ transaction: LedgerTransaction) -> Bool {
        guard transaction.type == .transfer,
              isBankAccount(account(withID: transaction.accountID)),
              let destination = account(withID: transaction.destinationAccountID) else {
            return false
        }
        return destination.group == .payments
    }

    func paymentSourceBalanceBefore(_ transaction: LedgerTransaction) -> Decimal? {
        guard isPaymentToBankTransfer(transaction),
              let sourceID = transaction.accountID else { return nil }
        guard let after = runningBalance(for: transaction.id, accountID: sourceID) else {
            return nil
        }
        return after + transaction.amount
    }

    func receivableCollectionAmount(_ transaction: LedgerTransaction) -> Decimal {
        guard let before = paymentSourceBalanceBefore(transaction), before > 0 else {
            return 0
        }
        return min(transaction.amount, before)
    }

    func paymentLoanIncreaseAmount(_ transaction: LedgerTransaction) -> Decimal {
        guard isPaymentToBankTransfer(transaction) else { return 0 }
        return max(0, transaction.amount - receivableCollectionAmount(transaction))
    }

    func paymentLoanPaymentAmount(_ transaction: LedgerTransaction) -> Decimal {
        guard isBankToPaymentTransfer(transaction) else { return 0 }
        return transaction.amount
    }

    private func isAmaraTransfer(_ transaction: LedgerTransaction) -> Bool {
''',
)

replace_once(
    store,
    '''        let loanAccountIDs = Set(accounts.filter {
            $0.group == .payments || $0.nature == .loan
        }.map(\.id))
''',
    '''        let loanAccountIDs = Set(accounts.filter {
            ($0.group == .payments && balance(for: $0) < 0) ||
                ($0.group != .payments && $0.nature == .loan)
        }.map(\.id))
''',
)


# Financial Summary: Total Money In and Total Money Out become the two main
# columns. Detail buckets are mutually exclusive:
# - Income excludes every Payments -> Bank transfer.
# - Payments -> Bank is split into Receivable Collected and Loan Increase.
# - Bank -> Payments is Loan Payments.
reports = "DailyLedger/Views/ReportsView.swift"
replace_once(
    reports,
    '''            HStack(alignment: .top, spacing: 12) {
                summaryColumn(
                    title: "Added",
                    color: AppTheme.green,
                    primaryTitle: "Income",
                    primaryValue: totals.income,
                    primaryKind: .income,
                    movements: loanIncreaseMovements
                )
                summaryColumn(
                    title: "Deducted",
                    color: AppTheme.red,
                    primaryTitle: "Expenses",
                    primaryValue: totals.expense,
                    primaryKind: .expenses,
                    movements: loanDecreaseMovements
                )
            }
''',
    '''            HStack(alignment: .top, spacing: 12) {
                moneyFlowColumn(
                    title: "Total Money In",
                    color: AppTheme.green,
                    totalValue: totalMoneyIn,
                    primaryTitle: "Income",
                    primaryValue: totals.income,
                    primaryKind: .income,
                    movementTitle: "Loan Increase",
                    movements: loanIncreaseMovements,
                    receivableMovements: receivableCollectionMovements
                )
                moneyFlowColumn(
                    title: "Total Money Out",
                    color: AppTheme.red,
                    totalValue: totalMoneyOut,
                    primaryTitle: "Expenses",
                    primaryValue: totals.expense,
                    primaryKind: .expenses,
                    movementTitle: "Loan Payments",
                    movements: loanPaymentMovements,
                    receivableMovements: []
                )
            }
''',
)

replace_range(
    reports,
    "    private var loanIncreaseMovements: [LoanNetMovement] {\n",
    "    private func summaryColumn(\n",
    r'''    private var loanIncreaseMovements: [LoanNetMovement] {
        paymentMovements { transaction in
            store.paymentLoanIncreaseAmount(transaction)
        }
    }

    private var receivableCollectionMovements: [LoanNetMovement] {
        paymentMovements { transaction in
            store.receivableCollectionAmount(transaction)
        }
    }

    private var loanPaymentMovements: [LoanNetMovement] {
        var totalsByCurrency: [String: Decimal] = [:]
        for transaction in store.transactions where selectedInterval.contains(transaction.date) {
            let amount = store.paymentLoanPaymentAmount(transaction)
            guard amount > 0,
                  let source = store.account(withID: transaction.accountID) else { continue }
            totalsByCurrency[source.currencyCode.uppercased(), default: 0] += amount
        }
        return movementRows(totalsByCurrency)
    }

    private func paymentMovements(
        amount: (LedgerTransaction) -> Decimal
    ) -> [LoanNetMovement] {
        var totalsByCurrency: [String: Decimal] = [:]
        for transaction in store.transactions where selectedInterval.contains(transaction.date) {
            let value = amount(transaction)
            guard value > 0,
                  let source = store.account(withID: transaction.accountID) else { continue }
            totalsByCurrency[source.currencyCode.uppercased(), default: 0] += value
        }
        return movementRows(totalsByCurrency)
    }

    private func movementRows(_ totals: [String: Decimal]) -> [LoanNetMovement] {
        totals.compactMap { currency, amount in
            guard amount > 0 else { return nil }
            return LoanNetMovement(currencyCode: currency, netAmount: amount)
        }.sorted { $0.currencyCode < $1.currencyCode }
    }

    private func convertedMovementTotal(_ movements: [LoanNetMovement]) -> Decimal {
        movements.reduce(Decimal.zero) { total, movement in
            guard let rate = store.fixedReportConversionRate(
                from: movement.currencyCode,
                to: store.currencyCode
            ) else { return total }
            return total + movement.netAmount * rate
        }
    }

    private var totalMoneyIn: Decimal {
        totals.income +
            convertedMovementTotal(loanIncreaseMovements) +
            convertedMovementTotal(receivableCollectionMovements)
    }

    private var totalMoneyOut: Decimal {
        totals.expense + convertedMovementTotal(loanPaymentMovements)
    }

''',
)

replace_range(
    reports,
    "    private func summaryColumn(\n",
    "    private func formulaOperator(_ symbol: String, color: Color) -> some View {\n",
    r'''    private func moneyFlowColumn(
        title: String,
        color: Color,
        totalValue: Decimal,
        primaryTitle: String,
        primaryValue: Decimal,
        primaryKind: PeriodTransactionKind,
        movementTitle: String,
        movements: [LoanNetMovement],
        receivableMovements: [LoanNetMovement]
    ) -> some View {
        VStack(spacing: 8) {
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
                compact: true
            )
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(color, lineWidth: 2.4)
            }

            formulaOperator("=", color: color)

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
                    compact: true
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .stroke(color.opacity(0.65), lineWidth: 2)
                }
            }
            .buttonStyle(.plain)

            formulaOperator("+", color: color)

            if movements.isEmpty {
                ReportTotalCard(
                    title: movementTitle,
                    value: 0,
                    currencyCode: store.currencyCode,
                    icon: primaryKind == .income
                        ? "arrow.up.right.circle.fill"
                        : "arrow.down.right.circle.fill",
                    color: color,
                    compact: true
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .stroke(color.opacity(0.65), lineWidth: 2)
                }
            } else {
                ForEach(Array(movements.enumerated()), id: \.element.id) { index, movement in
                    if index > 0 { formulaOperator("+", color: color) }
                    NavigationLink { LoanMovementReportView() } label: {
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

            if !receivableMovements.isEmpty {
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
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(color.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(color.opacity(0.65), lineWidth: 2)
        }
    }

    private func movementCard(
        title: String,
        movement: LoanNetMovement,
        icon: String,
        color: Color
    ) -> some View {
        ReportTotalCard(
            title: title,
            value: abs(movement.netAmount),
            currencyCode: movement.currencyCode,
            icon: icon,
            color: color,
            compact: true,
            secondaryText: movement.currencyCode.uppercased() == "PKR"
                ? "QAR: \(DisplayFormat.currency(abs(movement.netAmount) / Decimal(77), code: "QAR"))"
                : nil
        )
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(color.opacity(0.65), lineWidth: 2)
        }
    }

''',
)

replace_once(
    reports,
    '''    private var financeSummaryNetBalance: Decimal {
        totals.income + convertedLoanMovement - totals.expense + qatarClosingBalance
    }
''',
    '''    private var financeSummaryNetBalance: Decimal {
        totalMoneyIn - totalMoneyOut + qatarClosingBalance
    }
''',
)

replace_once(
    reports,
    '''    private var loanAccounts: [LedgerAccount] {
        store.accounts.filter { $0.group == .payments || $0.nature == .loan }
    }
''',
    '''    private var loanAccounts: [LedgerAccount] {
        store.accounts.filter {
            ($0.group == .payments && store.balance(for: $0) < 0) ||
                ($0.group != .payments && $0.nature == .loan)
        }
    }
''',
)


# Chart of Accounts: Payments accounts move automatically between Receivables
# and Payables based on live balance. Saved nature is ignored for Payments.
coa = "DailyLedger/Views/ChartOfAccountsView.swift"
replace_once(
    coa,
    '''private enum BalanceSheetBucket: String, CaseIterable, Identifiable {
    case bank
    case assets
    case loansPayments
    case liabilitiesOther
''',
    '''private enum BalanceSheetBucket: String, CaseIterable, Identifiable {
    case bank
    case assets
    case receivables
    case payables
    case liabilitiesOther
''',
)
replace_once(
    coa,
    '''        case .bank: return "Bank & Cash"
        case .assets: return "Assets"
        case .loansPayments: return "Loans & Payments"
        case .liabilitiesOther: return "Liabilities & Other"
''',
    '''        case .bank: return "Bank & Cash"
        case .assets: return "Assets"
        case .receivables: return "Receivables"
        case .payables: return "Payables & Loan Liabilities"
        case .liabilitiesOther: return "Liabilities & Other"
''',
)
replace_once(
    coa,
    '''        case .bank: return "BANK"
        case .assets: return "ASSET"
        case .loansPayments: return "LOAN"
        case .liabilitiesOther: return "OTHER"
''',
    '''        case .bank: return "BANK"
        case .assets: return "ASSET"
        case .receivables: return "RECV"
        case .payables: return "PAY"
        case .liabilitiesOther: return "OTHER"
''',
)
replace_once(
    coa,
    '''        case .bank: return "building.columns.fill"
        case .assets: return "house.fill"
        case .loansPayments: return "creditcard.trianglebadge.exclamationmark"
        case .liabilitiesOther: return "list.bullet.rectangle.portrait.fill"
''',
    '''        case .bank: return "building.columns.fill"
        case .assets: return "house.fill"
        case .receivables: return "person.crop.circle.badge.clock.fill"
        case .payables: return "creditcard.trianglebadge.exclamationmark"
        case .liabilitiesOther: return "list.bullet.rectangle.portrait.fill"
''',
)
replace_once(
    coa,
    '''                subtitle: "Bank, assets, loans, payments and liabilities",
''',
    '''                subtitle: "Bank, assets, receivables, payables and liabilities",
''',
)
replace_once(
    coa,
    '''            Text("Balance Sheet order: Bank & Cash, Assets, Loans & Payments, then Liabilities & Other. Main-account totals remain separated by currency.")
''',
    '''            Text("Payments move automatically: positive balances are Receivables and negative balances are Payables. Native account nature remains unchanged.")
''',
)
replace_once(
    coa,
    '''    private func effectiveBucket(for account: LedgerAccount) -> BalanceSheetBucket {
        if let parent = store.account(withID: account.parentAccountID) {
            return directBucket(for: parent)
        }
        return directBucket(for: account)
    }
''',
    '''    private func effectiveBucket(for account: LedgerAccount) -> BalanceSheetBucket {
        if account.group == .payments {
            return directBucket(for: account)
        }
        if let parent = store.account(withID: account.parentAccountID) {
            return directBucket(for: parent)
        }
        return directBucket(for: account)
    }
''',
)
replace_once(
    coa,
    '''    private func directBucket(for account: LedgerAccount) -> BalanceSheetBucket {
        let nature = account.nature ?? .unassigned
        if nature == .loan || account.group == .payments { return .loansPayments }
        if nature == .asset || account.group == .assets { return .assets }
        if nature == .bank || account.group == .qatar || account.group == .pakistan { return .bank }
        return .liabilitiesOther
    }
''',
    '''    private func directBucket(for account: LedgerAccount) -> BalanceSheetBucket {
        let nature = account.nature ?? .unassigned
        if account.group == .payments {
            let current = store.balance(for: account)
            if current < 0 { return .payables }
            if current > 0 { return .receivables }
            return account.openingBalance < 0 ? .payables : .receivables
        }
        if nature == .loan || nature == .payable { return .payables }
        if nature == .receivable { return .receivables }
        if nature == .asset || account.group == .assets { return .assets }
        if nature == .bank || account.group == .qatar || account.group == .pakistan { return .bank }
        return .liabilitiesOther
    }
''',
)

print("Classified Payments by live balance and rebuilt Financial Summary with non-duplicating Money In/Out buckets.")
