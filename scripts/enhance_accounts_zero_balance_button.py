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


accounts = "DailyLedger/Views/AccountsView.swift"

# Make the zero-balance filter obvious instead of relying on an eye-only icon.
replace_once(
    accounts,
    r'''                ToolbarItem(placement: .navigationBarLeading) {
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
''',
    r'''                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            hideZeroBalanceAccounts.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: hideZeroBalanceAccounts
                                ? "eye.slash.circle.fill"
                                : "eye.circle")
                            Text(hideZeroBalanceAccounts ? "Show All" : "Hide Zero")
                                .font(.caption.bold())
                        }
                    }
                    .tint(hideZeroBalanceAccounts ? AppTheme.purple : .primary)
                    .accessibilityLabel(hideZeroBalanceAccounts
                        ? "Show all accounts"
                        : "Hide zero-balance accounts")
                }
''',
)

# Treat balances that display as 0.00 as zero. Parents remain visible whenever
# their own balance or any direct child's balance is non-zero.
replace_once(
    accounts,
    r'''    private func shouldShowWithZeroFilter(_ account: LedgerAccount) -> Bool {
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
    r'''    private func shouldShowWithZeroFilter(_ account: LedgerAccount) -> Bool {
        if account.parentAccountID != nil {
            return !isEffectivelyZeroBalance(store.balance(for: account))
        }
        if !isEffectivelyZeroBalance(store.balance(for: account)) {
            return true
        }
        return store.subAccounts(of: account.id).contains {
            !isEffectivelyZeroBalance(store.balance(for: $0))
        }
    }

    private func isEffectivelyZeroBalance(_ value: Decimal) -> Bool {
        var input = value
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &input, 2, .plain)
        return rounded == 0
    }
''',
)

print("Made the Accounts zero-balance filter button explicit and rounded zero checks to two decimals.")
