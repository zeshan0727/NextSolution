from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    (ROOT / path).write_text(content, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected exactly one match in {path}, found {count}: {old[:240]!r}")
    write(path, text.replace(old, new, 1))


# ---------------------------------------------------------------------------
# Version: app-only reporting fix. RootHide SMS daemon remains 2.2.1.
# ---------------------------------------------------------------------------
replace_once("project.yml", 'MARKETING_VERSION: "1.3.59"', 'MARKETING_VERSION: "1.3.60"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "67"', 'CURRENT_PROJECT_VERSION: "68"')


# ---------------------------------------------------------------------------
# LedgerStore: add strict Financial Summary classifiers.
# IMPORTANT: Payments-group membership is NOT enough to be a loan here.
# Only AccountNature.loan participates in Loans Increased / Loans Paid.
# ---------------------------------------------------------------------------
store = "DailyLedger/Services/LedgerStore.swift"
anchor = '''    func isBankAccount(_ account: LedgerAccount?) -> Bool {
        account?.nature == .bank
    }
'''
insert = anchor + '''
    /// Financial Summary cash-flow classification is intentionally stricter than
    /// the general reports. Direct income/expense must be an explicit transaction,
    /// refunds are separated, and only Bank <-> Loan transfers affect loan cash flow.
    func isFinancialSummaryDirectIncome(_ transaction: LedgerTransaction) -> Bool {
        transaction.type == .income && transaction.refundOfTransactionID == nil
    }

    func isFinancialSummaryRefund(_ transaction: LedgerTransaction) -> Bool {
        transaction.type == .income && transaction.refundOfTransactionID != nil
    }

    func isFinancialSummaryDirectExpense(_ transaction: LedgerTransaction) -> Bool {
        transaction.type == .expense && transaction.refundOfTransactionID == nil
    }

    func financialSummaryLoanIncreaseAmount(_ transaction: LedgerTransaction) -> Decimal {
        guard transaction.type == .transfer,
              let source = account(withID: transaction.accountID),
              let destination = account(withID: transaction.destinationAccountID),
              source.nature == .loan,
              destination.nature == .bank else { return 0 }
        return transaction.amount
    }

    func financialSummaryLoanPaidAmount(_ transaction: LedgerTransaction) -> Decimal {
        guard transaction.type == .transfer,
              let source = account(withID: transaction.accountID),
              let destination = account(withID: transaction.destinationAccountID),
              source.nature == .bank,
              destination.nature == .loan else { return 0 }
        return transaction.amount
    }

    func convertedFinancialSummaryLoanIncreaseAmount(_ transaction: LedgerTransaction) -> Decimal? {
        let amount = financialSummaryLoanIncreaseAmount(transaction)
        guard amount > 0,
              let source = account(withID: transaction.accountID),
              let rate = fixedReportConversionRate(from: source.currencyCode, to: currencyCode) else {
            return nil
        }
        return amount * rate
    }

    func convertedFinancialSummaryLoanPaidAmount(_ transaction: LedgerTransaction) -> Decimal? {
        let amount = financialSummaryLoanPaidAmount(transaction)
        guard amount > 0,
              let source = account(withID: transaction.accountID),
              let rate = fixedReportConversionRate(from: source.currencyCode, to: currencyCode) else {
            return nil
        }
        return amount * rate
    }
'''
replace_once(store, anchor, insert)


# ---------------------------------------------------------------------------
# Financial Summary UI/calculation.
# ---------------------------------------------------------------------------
reports = "DailyLedger/Views/ReportsView.swift"
replace_once(
    reports,
    '''                moneyFlowColumn(
                    title: "Total Money In",
                    color: AppTheme.green,
                    totalValue: totalMoneyIn,
                    primaryTitle: "Income",
                    primaryValue: totals.income,
                    primaryKind: .income,
                    movementTitle: "Loan Increase",
                    movements: loanIncreaseMovements
                )
                moneyFlowColumn(
                    title: "Total Money Out",
                    color: AppTheme.red,
                    totalValue: totalMoneyOut,
                    primaryTitle: "Expenses",
                    primaryValue: totals.expense,
                    primaryKind: .expenses,
                    movementTitle: "Loan Decrease",
                    movements: loanDecreaseMovements
                )
''',
    '''                moneyFlowColumn(
                    title: "Total Income",
                    color: AppTheme.green,
                    totalValue: totalMoneyIn,
                    primaryTitle: "Income",
                    primaryValue: financialSummaryDirectIncomeTotal,
                    primaryKind: .income,
                    movementTitle: "Loans Increased",
                    movements: loanIncreaseMovements
                )
                moneyFlowColumn(
                    title: "Total Money Out",
                    color: AppTheme.red,
                    totalValue: totalMoneyOut,
                    primaryTitle: "Expenses",
                    primaryValue: financialSummaryDirectExpenseTotal,
                    primaryKind: .expenses,
                    movementTitle: "Loans Paid",
                    movements: loanDecreaseMovements
                )
'''
)

replace_once(
    reports,
    '''    private var qatarClosingBalance: Decimal {
        store.combinedBalance(for: closingBalanceAccounts, before: closingBalanceCutoff)
    }

    private var loanIncreaseMovements: [LoanNetMovement] {
''',
    '''    private var qatarClosingBalance: Decimal {
        store.combinedBalance(for: closingBalanceAccounts, before: closingBalanceCutoff)
    }

    private var financialSummaryDirectIncomeTotal: Decimal {
        store.transactions.lazy
            .filter { selectedInterval.contains($0.date) && store.isFinancialSummaryDirectIncome($0) }
            .reduce(Decimal.zero) { $0 + (store.convertedReportIncomeAmount($1) ?? 0) }
    }

    private var financialSummaryRefundTotal: Decimal {
        store.transactions.lazy
            .filter { selectedInterval.contains($0.date) && store.isFinancialSummaryRefund($0) }
            .reduce(Decimal.zero) { $0 + (store.convertedReportIncomeAmount($1) ?? 0) }
    }

    private var financialSummaryDirectExpenseTotal: Decimal {
        store.transactions.lazy
            .filter { selectedInterval.contains($0.date) && store.isFinancialSummaryDirectExpense($0) }
            .reduce(Decimal.zero) { $0 + (store.convertedReportExpenseAmount($1) ?? 0) }
    }

    private var loanIncreaseMovements: [LoanNetMovement] {
'''
)

replace_once(
    reports,
    '''            let value = increase
                ? store.loanIncreaseAmount(transaction)
                : store.loanDecreaseAmount(transaction)
''',
    '''            let value = increase
                ? store.financialSummaryLoanIncreaseAmount(transaction)
                : store.financialSummaryLoanPaidAmount(transaction)
'''
)

replace_once(
    reports,
    '''    private var totalMoneyIn: Decimal {
        totals.income + convertedMovementTotal(loanIncreaseMovements)
    }

    private var totalMoneyOut: Decimal {
        totals.expense + convertedMovementTotal(loanDecreaseMovements)
    }
''',
    '''    private var totalMoneyIn: Decimal {
        financialSummaryDirectIncomeTotal
            + financialSummaryRefundTotal
            + convertedMovementTotal(loanIncreaseMovements)
    }

    private var totalMoneyOut: Decimal {
        financialSummaryDirectExpenseTotal
            + convertedMovementTotal(loanDecreaseMovements)
    }
'''
)

replace_once(
    reports,
    '''            formulaOperator("+", color: color)

            if movements.isEmpty {
''',
    '''            if primaryKind == .income {
                formulaOperator("+", color: color)
                NavigationLink {
                    PeriodTransactionsView(kind: .refunds, interval: selectedInterval)
                } label: {
                    ReportTotalCard(
                        title: "Refunds",
                        value: financialSummaryRefundTotal,
                        currencyCode: store.currencyCode,
                        icon: "arrow.uturn.backward.circle.fill",
                        color: color,
                        compact: true
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .stroke(color.opacity(0.65), lineWidth: 2)
                    }
                }
                .buttonStyle(.plain)
            }

            formulaOperator("+", color: color)

            if movements.isEmpty {
'''
)

replace_once(
    reports,
    '''                    NavigationLink { LoanMovementReportView() } label: {
                        movementCard(
''',
    '''                    NavigationLink {
                        PeriodTransactionsView(
                            kind: primaryKind == .income ? .loanIncreased : .loans,
                            interval: selectedInterval
                        )
                    } label: {
                        movementCard(
'''
)


# ---------------------------------------------------------------------------
# Card drill-down: exact components only.
# ---------------------------------------------------------------------------
period = "DailyLedger/Views/PeriodTransactionsView.swift"
replace_once(
    period,
    '''enum PeriodTransactionKind {
    case income
    case expenses
    case loans

    var title: String {
        switch self {
        case .income: return "Income"
        case .expenses: return "Expenses"
        case .loans: return "Loans Paid"
        }
    }
}
''',
    '''enum PeriodTransactionKind {
    case income
    case refunds
    case expenses
    case loanIncreased
    case loans

    var title: String {
        switch self {
        case .income: return "Income"
        case .refunds: return "Refunds"
        case .expenses: return "Expenses"
        case .loanIncreased: return "Loans Increased"
        case .loans: return "Loans Paid"
        }
    }
}
'''
)

replace_once(
    period,
    '''                            accountID: kind == .income ? store.reportIncomeAccountID(transaction) : nil
''',
    '''                            accountID: (kind == .income || kind == .refunds)
                                ? store.reportIncomeAccountID(transaction)
                                : nil
'''
)

replace_once(
    period,
    '''            switch kind {
            case .income:
                kindMatches = store.convertedReportIncomeAmount(transaction) != nil
            case .expenses:
                kindMatches = store.convertedReportExpenseAmount(transaction) != nil
            case .loans:
                kindMatches = transaction.type == .transfer &&
                    store.account(withID: transaction.destinationAccountID)?.group == .payments
            }
''',
    '''            switch kind {
            case .income:
                kindMatches = store.isFinancialSummaryDirectIncome(transaction) &&
                    store.convertedReportIncomeAmount(transaction) != nil
            case .refunds:
                kindMatches = store.isFinancialSummaryRefund(transaction) &&
                    store.convertedReportIncomeAmount(transaction) != nil
            case .expenses:
                kindMatches = store.isFinancialSummaryDirectExpense(transaction) &&
                    store.convertedReportExpenseAmount(transaction) != nil
            case .loanIncreased:
                kindMatches = store.convertedFinancialSummaryLoanIncreaseAmount(transaction) != nil
            case .loans:
                kindMatches = store.convertedFinancialSummaryLoanPaidAmount(transaction) != nil
            }
'''
)

replace_once(
    period,
    '''            switch kind {
            case .income:
                return $0 + (store.convertedReportIncomeAmount($1) ?? 0)
            case .expenses:
                return $0 + (store.convertedReportExpenseAmount($1) ?? 0)
            case .loans:
                return $0 + $1.amount
            }
''',
    '''            switch kind {
            case .income, .refunds:
                return $0 + (store.convertedReportIncomeAmount($1) ?? 0)
            case .expenses:
                return $0 + (store.convertedReportExpenseAmount($1) ?? 0)
            case .loanIncreased:
                return $0 + (store.convertedFinancialSummaryLoanIncreaseAmount($1) ?? 0)
            case .loans:
                return $0 + (store.convertedFinancialSummaryLoanPaidAmount($1) ?? 0)
            }
'''
)

print("Prepared Next Ledger 1.3.60: direct Income + Refunds + Loans Increased; direct Expenses + Loans Paid; internal transfers excluded from Financial Summary.")
