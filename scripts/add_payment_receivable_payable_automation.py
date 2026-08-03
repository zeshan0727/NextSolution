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
            f"Expected one match in {relative}, found {count}: {old[:200]!r}"
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


# ---------------------------------------------------------------------------
# Account model: separate amounts due to the user from amounts owed by the user.
# Legacy Loan accounts remain supported and are treated as Payables until edited.
# ---------------------------------------------------------------------------
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
        case .loan: return "Loan (Legacy)"
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


# ---------------------------------------------------------------------------
# Accounts tab and account editor.
# Payments are shown under Receivables and Payables without adding new collapse
# controls. Selecting Payment Type automatically owns the account nature.
# ---------------------------------------------------------------------------
accounts = "DailyLedger/Views/AccountsView.swift"
replace_once(
    accounts,
    "import SwiftUI\n\nstruct AccountsView: View {\n",
    '''import SwiftUI

private enum PaymentAccountType: String, CaseIterable, Identifiable {
    case receivable
    case payable

    var id: String { rawValue }
    var title: String { self == .receivable ? "Receivable" : "Payable" }
    var pluralTitle: String { self == .receivable ? "Receivables" : "Payables" }
    var nature: AccountNature { self == .receivable ? .receivable : .payable }
    var icon: String {
        self == .receivable
            ? "arrow.down.left.circle.fill"
            : "arrow.up.right.circle.fill"
    }

    static func effective(for account: LedgerAccount, parent: LedgerAccount? = nil) -> PaymentAccountType {
        let nature = parent?.nature ?? account.nature
        return nature == .receivable ? .receivable : .payable
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

    private func paymentAccounts(_ type: PaymentAccountType) -> [LedgerAccount] {
        accounts(in: .payments).filter { account in
            PaymentAccountType.effective(
                for: account,
                parent: store.account(withID: account.parentAccountID)
            ) == type
        }
    }

    private func paymentGroupHeader(
        _ type: PaymentAccountType,
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

replace_once(
    accounts,
    '''    @State private var nature: AccountNature = .unassigned
    @State private var chartCode = ""
    @State private var parentAccountID: UUID?
''',
    '''    @State private var nature: AccountNature = .unassigned
    @State private var paymentType: PaymentAccountType = .receivable
    @State private var chartCode = ""
    @State private var parentAccountID: UUID?
''',
)

replace_once(
    accounts,
    '''        _nature = State(initialValue: account?.nature ?? .unassigned)
        _chartCode = State(initialValue: account?.chartCode ?? "")
        _parentAccountID = State(initialValue: account?.parentAccountID ?? initialParentAccountID)
''',
    '''        _nature = State(initialValue: account?.nature ?? .unassigned)
        _paymentType = State(initialValue:
            account?.nature == .receivable || (account == nil && initialGroup == .payments)
                ? .receivable
                : .payable
        )
        _chartCode = State(initialValue: account?.chartCode ?? "")
        _parentAccountID = State(initialValue: account?.parentAccountID ?? initialParentAccountID)
''',
)

replace_once(
    accounts,
    '''                    Picker("Account Nature", selection: $nature) {
                        ForEach(AccountNature.allCases) { Text($0.title).tag($0) }
                    }
''',
    '''                    if group == .payments {
                        Picker("Payment Type", selection: $paymentType) {
                            ForEach(PaymentAccountType.allCases) { type in
                                Label(type.title, systemImage: type.icon).tag(type)
                            }
                        }
                        .disabled(selectedParent?.group == .payments)
                        LabeledContent(
                            "Account Nature",
                            value: resolvedNature?.title ?? paymentType.nature.title
                        )
                        Text(paymentType == .receivable
                            ? "Receivable means this person or account owes money to you. Collections reduce its balance."
                            : "Payable means you owe this person or account. Money received can increase the payable or loan balance.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Account Nature", selection: $nature) {
                            ForEach(AccountNature.allCases) { value in
                                if value != .receivable && value != .payable && value != .loan {
                                    Text(value.title).tag(value)
                                }
                            }
                        }
                    }
''',
)

replace_once(
    accounts,
    '''            .onChange(of: parentAccountID) { _ in
                if let parent = selectedParent {
                    group = parent.group
                }
            }
''',
    '''            .onChange(of: parentAccountID) { _ in
                if let parent = selectedParent {
                    group = parent.group
                    if parent.group == .payments {
                        paymentType = PaymentAccountType.effective(for: parent)
                        nature = paymentType.nature
                    }
                }
            }
            .onChange(of: group) { value in
                if value == .payments {
                    nature = paymentType.nature
                }
            }
            .onChange(of: paymentType) { value in
                if group == .payments {
                    nature = value.nature
                }
            }
''',
)

replace_once(
    accounts,
    '''    private var parsedOpeningBalance: Decimal? {
''',
    '''    private var resolvedNature: AccountNature? {
        if group == .payments {
            if let parent = selectedParent, parent.group == .payments {
                return PaymentAccountType.effective(for: parent).nature
            }
            return paymentType.nature
        }
        return nature == .unassigned ? nil : nature
    }

    private var parsedOpeningBalance: Decimal? {
''',
)

text = read(accounts)
old_nature = "nature == .unassigned ? nil : nature"
count = text.count(old_nature)
if count != 2:
    raise RuntimeError(f"Expected two account-save nature expressions, found {count}")
write(accounts, text.replace(old_nature, "resolvedNature"))


# ---------------------------------------------------------------------------
# Reporting rules.
# Payments -> Bank is report income. Only Payable/legacy Loan accounts affect
# loan movement cards. Receivables reduce normally but do not become loan growth.
# ---------------------------------------------------------------------------
store = "DailyLedger/Services/LedgerStore.swift"
replace_once(
    store,
    '''    func isReportIncome(_ transaction: LedgerTransaction) -> Bool {
        transaction.type == .income || isAmaraTransfer(transaction)
    }
''',
    '''    func isReportIncome(_ transaction: LedgerTransaction) -> Bool {
        transaction.type == .income || isReportTransferIncome(transaction)
    }
''',
)
replace_once(
    store,
    '''    func reportIncomeAmount(_ transaction: LedgerTransaction) -> Decimal {
        isAmaraTransfer(transaction)
            ? (transaction.destinationAmount ?? transaction.amount)
            : transaction.amount
    }

    func reportIncomeAccountID(_ transaction: LedgerTransaction) -> UUID? {
        isAmaraTransfer(transaction) ? transaction.destinationAccountID : transaction.accountID
    }
''',
    '''    func reportIncomeAmount(_ transaction: LedgerTransaction) -> Decimal {
        isReportTransferIncome(transaction)
            ? (transaction.destinationAmount ?? transaction.amount)
            : transaction.amount
    }

    func reportIncomeAccountID(_ transaction: LedgerTransaction) -> UUID? {
        isReportTransferIncome(transaction) ? transaction.destinationAccountID : transaction.accountID
    }
''',
)
replace_once(
    store,
    '''    private func isAmaraTransfer(_ transaction: LedgerTransaction) -> Bool {
''',
    '''    func isPayableAccount(_ account: LedgerAccount?) -> Bool {
        guard let account else { return false }
        if account.nature == .receivable { return false }
        return account.nature == .payable ||
            account.nature == .loan ||
            account.group == .payments
    }

    func isReceivableAccount(_ account: LedgerAccount?) -> Bool {
        guard let account else { return false }
        return account.nature == .receivable
    }

    func isPaymentToBankTransfer(_ transaction: LedgerTransaction) -> Bool {
        guard transaction.type == .transfer,
              let source = account(withID: transaction.accountID),
              let destination = account(withID: transaction.destinationAccountID),
              source.group == .payments else { return false }
        return destination.nature == .bank ||
            destination.group == .qatar ||
            destination.group == .pakistan
    }

    private func isReportTransferIncome(_ transaction: LedgerTransaction) -> Bool {
        isAmaraTransfer(transaction) || isPaymentToBankTransfer(transaction)
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
            isPayableAccount($0)
        }.map(\.id))
''',
)

reports = "DailyLedger/Views/ReportsView.swift"
replace_once(
    reports,
    '''        let loanAccountIDs = Set(store.accounts.filter {
            $0.group == .payments || $0.nature == .loan
        }.map(\.id))
''',
    '''        let loanAccountIDs = Set(store.accounts.filter {
            store.isPayableAccount($0)
        }.map(\.id))
''',
)
replace_once(
    reports,
    '''    private var loanAccounts: [LedgerAccount] {
        store.accounts.filter { $0.group == .payments || $0.nature == .loan }
    }
''',
    '''    private var loanAccounts: [LedgerAccount] {
        store.accounts.filter { store.isPayableAccount($0) }
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
        totals.income + convertedLoanMovement - totals.expense + qatarClosingBalance
            - payableToBankIncomeOverlap
    }

    private var payableToBankIncomeOverlap: Decimal {
        store.transactions.lazy.filter {
            selectedInterval.contains($0.date) &&
            store.isPaymentToBankTransfer($0) &&
            store.isPayableAccount(store.account(withID: $0.accountID))
        }.reduce(Decimal.zero) {
            $0 + (store.convertedReportIncomeAmount($1) ?? 0)
        }
    }
''',
)
replace_once(
    reports,
    '''    private func effectiveNature(_ account: LedgerAccount) -> AccountNature {
        if account.group == .payments { return .loan }
        if account.group == .assets { return .asset }
        return account.nature ?? .unassigned
    }
''',
    '''    private func effectiveNature(_ account: LedgerAccount) -> AccountNature {
        if account.group == .payments {
            return account.nature == .receivable ? .receivable : .payable
        }
        if account.group == .assets { return .asset }
        return account.nature ?? .unassigned
    }
''',
)
replace_once(
    reports,
    '''        Set(store.accounts.filter {
            if $0.group == .payments { return nature == .loan }
            if $0.group == .assets { return nature == .asset }
            return $0.nature == nature
        }.map(\.id))
''',
    '''        Set(store.accounts.filter {
            if $0.group == .payments {
                let effective: AccountNature = $0.nature == .receivable ? .receivable : .payable
                return nature == effective
            }
            if $0.group == .assets { return nature == .asset }
            return $0.nature == nature
        }.map(\.id))
''',
)


# ---------------------------------------------------------------------------
# Chart of Accounts: separate Receivables (asset) and Payables (liability).
# Existing statement/account disclosure behavior remains untouched.
# ---------------------------------------------------------------------------
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
    '''            Text("Balance Sheet order: Bank & Cash, Assets, Receivables, Payables & Loan Liabilities, then Liabilities & Other. Main-account totals remain separated by currency.")
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
        if nature == .receivable { return .receivables }
        if nature == .payable || nature == .loan { return .payables }
        if account.group == .payments {
            return nature == .receivable ? .receivables : .payables
        }
        if nature == .asset || account.group == .assets { return .assets }
        if nature == .bank || account.group == .qatar || account.group == .pakistan { return .bank }
        return .liabilitiesOther
    }
''',
)

print("Added Receivable/Payable automation, payment grouping, COA placement, and payment-to-bank income rules.")
