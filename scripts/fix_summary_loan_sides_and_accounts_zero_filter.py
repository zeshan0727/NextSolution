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
            f"Expected one match in {relative}, found {count}: {old[:180]!r}"
        )
    write(relative, text.replace(old, new, 1))


# Financial Summary: do not net loan increases and repayments together before
# choosing a side. Gross increases always appear under Added; gross repayments
# always appear under Deducted. Net movement is still used for Net Balance.
reports = "DailyLedger/Views/ReportsView.swift"
replace_once(
    reports,
    r'''    private var loanIncreaseMovements: [LoanNetMovement] {
        store.loanNetMovements(in: selectedInterval).filter { $0.netAmount > 0 }
    }

    private var loanDecreaseMovements: [LoanNetMovement] {
        store.loanNetMovements(in: selectedInterval).filter { $0.netAmount < 0 }
    }
''',
    r'''    private var loanIncreaseMovements: [LoanNetMovement] {
        grossLoanMovements(increase: true)
    }

    private var loanDecreaseMovements: [LoanNetMovement] {
        grossLoanMovements(increase: false)
    }

    private func grossLoanMovements(increase: Bool) -> [LoanNetMovement] {
        let loanAccountIDs = Set(store.accounts.filter {
            $0.group == .payments || $0.nature == .loan
        }.map(\.id))
        var totals: [String: Decimal] = [:]

        for transaction in store.transactions where selectedInterval.contains(transaction.date) {
            if increase,
               let sourceID = transaction.accountID,
               loanAccountIDs.contains(sourceID),
               transaction.type == .expense || transaction.type == .transfer,
               let source = store.account(withID: sourceID) {
                totals[source.currencyCode.uppercased(), default: 0] += transaction.amount
            }

            if !increase,
               transaction.type == .transfer,
               let destinationID = transaction.destinationAccountID,
               loanAccountIDs.contains(destinationID),
               let destination = store.account(withID: destinationID) {
                totals[destination.currencyCode.uppercased(), default: 0] +=
                    transaction.destinationAmount ?? transaction.amount
            }
        }

        return totals.compactMap { currency, amount in
            guard amount > 0 else { return nil }
            return LoanNetMovement(currencyCode: currency, netAmount: amount)
        }.sorted { $0.currencyCode < $1.currencyCode }
    }
''',
)


# Accounts tab: persistent eye button hides zero-balance accounts. A parent is
# retained whenever its own balance or any direct child's balance is non-zero;
# zero children hide individually.
accounts = "DailyLedger/Views/AccountsView.swift"
replace_once(
    accounts,
    r'''    @State private var showingTransfer = false
    @State private var searchText = ""
''',
    r'''    @State private var showingTransfer = false
    @State private var searchText = ""
    @AppStorage("AccountsHideZeroBalance") private var hideZeroBalanceAccounts = false
''',
)

replace_once(
    accounts,
    r'''            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { addingAccount = true } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add account")
                }
            }
''',
    r'''            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        hideZeroBalanceAccounts.toggle()
                    } label: {
                        Image(systemName: hideZeroBalanceAccounts
                            ? "eye.slash.circle.fill"
                            : "eye.circle")
                    }
                    .tint(hideZeroBalanceAccounts ? AppTheme.purple : .primary)
                    .accessibilityLabel(hideZeroBalanceAccounts
                        ? "Show zero-balance accounts"
                        : "Hide zero-balance accounts")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { addingAccount = true } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add account")
                }
            }
''',
)

replace_once(
    accounts,
    r'''    private func accounts(in group: AccountGroup) -> [LedgerAccount] {
        let matching = store.activeAccounts.filter {
            $0.group == group && (searchText.isEmpty ||
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.currencyCode.localizedCaseInsensitiveContains(searchText) ||
                (store.account(withID: $0.parentAccountID)?.name.localizedCaseInsensitiveContains(searchText) ?? false))
        }
        let mainAccounts = matching.filter { $0.parentAccountID == nil }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        var ordered: [LedgerAccount] = []
        for main in mainAccounts {
            ordered.append(main)
            ordered.append(contentsOf: matching.filter { $0.parentAccountID == main.id }.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            })
        }
        let included = Set(ordered.map(\.id))
        ordered.append(contentsOf: matching.filter { !included.contains($0.id) }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })
        return ordered
    }
''',
    r'''    private func accounts(in group: AccountGroup) -> [LedgerAccount] {
        let matching = store.activeAccounts.filter {
            guard $0.group == group else { return false }
            guard !hideZeroBalanceAccounts || shouldShowWithZeroFilter($0) else { return false }
            return searchText.isEmpty ||
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.currencyCode.localizedCaseInsensitiveContains(searchText) ||
                (store.account(withID: $0.parentAccountID)?.name.localizedCaseInsensitiveContains(searchText) ?? false)
        }
        let mainAccounts = matching.filter { $0.parentAccountID == nil }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        var ordered: [LedgerAccount] = []
        for main in mainAccounts {
            ordered.append(main)
            ordered.append(contentsOf: matching.filter { $0.parentAccountID == main.id }.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            })
        }
        let included = Set(ordered.map(\.id))
        ordered.append(contentsOf: matching.filter { !included.contains($0.id) }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })
        return ordered
    }

    private func shouldShowWithZeroFilter(_ account: LedgerAccount) -> Bool {
        if account.parentAccountID != nil {
            return store.balance(for: account) != 0
        }
        if store.balance(for: account) != 0 {
            return true
        }
        return store.subAccounts(of: account.id).contains {
            store.balance(for: $0) != 0
        }
    }
''',
)

print("Separated gross loan summary sides and added the Accounts zero-balance filter button.")
