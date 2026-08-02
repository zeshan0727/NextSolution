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
        raise RuntimeError(f"Expected one match in {relative}, found {count}: {old[:160]!r}")
    write(relative, text.replace(old, new, 1))


def replace_range(relative: str, start_marker: str, end_marker: str, replacement: str) -> None:
    text = read(relative)
    start = text.find(start_marker)
    if start < 0:
        raise RuntimeError(f"Start marker not found in {relative}: {start_marker[:120]!r}")
    end = text.find(end_marker, start)
    if end < 0:
        raise RuntimeError(f"End marker not found in {relative}: {end_marker[:120]!r}")
    write(relative, text[:start] + replacement + text[end:])


path = "DailyLedger/Views/ChartOfAccountsView.swift"

# Both accounting statements and all account families start collapsed.
replace_once(
    path,
    '''    @State private var searchText = ""
    @State private var editor: ChartEditorDestination?
''',
    '''    @State private var searchText = ""
    @State private var editor: ChartEditorDestination?
    @State private var incomeStatementExpanded = false
    @State private var balanceSheetExpanded = false
    @State private var expandedMainAccountIDs: Set<UUID> = []
''',
)

replace_range(
    path,
    "    private var incomeStatementSection: some View {",
    "    private var balanceSheetSection: some View {",
    r'''    private var incomeStatementSection: some View {
        Section {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    incomeStatementExpanded.toggle()
                }
            } label: {
                statementDisclosureHeader(
                    title: "Income Statement",
                    subtitle: "Income and expense accounts",
                    icon: "chart.line.uptrend.xyaxis",
                    isExpanded: incomeStatementExpanded
                )
            }
            .buttonStyle(.plain)

            if incomeStatementExpanded {
                statementGroupHeader(
                    title: "Income",
                    icon: "arrow.down.left.circle.fill",
                    total: transactionTypeTotalsText(type: .income),
                    tint: AppTheme.green
                )
                let incomeCategories = filteredCategories(.income)
                if incomeCategories.isEmpty {
                    Text("No matching income categories.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(incomeCategories, id: \.self) { category in
                        categoryRow(category, type: .income)
                    }
                }

                statementGroupHeader(
                    title: "Expenses",
                    icon: "arrow.up.right.circle.fill",
                    total: transactionTypeTotalsText(type: .expense),
                    tint: AppTheme.red
                )
                let expenseCategories = filteredCategories(.expense)
                if expenseCategories.isEmpty {
                    Text("No matching expense categories.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(expenseCategories, id: \.self) { category in
                        categoryRow(category, type: .expense)
                    }
                }
            }
        } footer: {
            if incomeStatementExpanded {
                Text("Income and expense categories are presented together as the Income Statement.")
            }
        }
    }

''',
)

replace_range(
    path,
    "    private var balanceSheetSection: some View {",
    "    private func majorHeader(title: String, subtitle: String, icon: String) -> some View {",
    r'''    private var balanceSheetSection: some View {
        Section {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    balanceSheetExpanded.toggle()
                }
            } label: {
                statementDisclosureHeader(
                    title: "Balance Sheet",
                    subtitle: "Bank, assets, loans, payments and liabilities",
                    icon: "building.columns.circle.fill",
                    isExpanded: balanceSheetExpanded
                )
            }
            .buttonStyle(.plain)

            if balanceSheetExpanded {
                ForEach(BalanceSheetBucket.allCases) { bucket in
                    let accounts = orderedAccounts(for: bucket)
                    balanceGroupHeader(
                        bucket: bucket,
                        total: accountTotalsText(accounts),
                        count: accounts.count
                    )
                    if accounts.isEmpty {
                        Text("No matching \(bucket.title.lowercased()) accounts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        accountHierarchyRows(accounts, bucket: bucket)
                    }
                }
            }
        } footer: {
            if balanceSheetExpanded {
                Text("Balance Sheet order: Bank & Cash, Assets, Loans & Payments, then Liabilities & Other. Main-account totals remain separated by currency.")
            }
        }
    }

''',
)

replace_range(
    path,
    "    private func majorHeader(title: String, subtitle: String, icon: String) -> some View {",
    "    private func statementGroupHeader(",
    r'''    private func statementDisclosureHeader(
        title: String,
        subtitle: String,
        icon: String,
        isExpanded: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.purple)
                .frame(width: 18)
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppTheme.purple)
                .frame(width: 34, height: 34)
                .background(AppTheme.purple.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(isExpanded ? "Collapse" : "Show all")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.purple)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .textCase(nil)
    }

''',
)

replace_range(
    path,
    "    private func accountRow(_ account: LedgerAccount, bucket: BalanceSheetBucket) -> some View {",
    "    private func orderedAccounts(for bucket: BalanceSheetBucket) -> [LedgerAccount] {",
    r'''    @ViewBuilder
    private func accountHierarchyRows(
        _ accounts: [LedgerAccount],
        bucket: BalanceSheetBucket
    ) -> some View {
        ForEach(topLevelAccounts(in: accounts)) { account in
            let children = childAccounts(of: account, in: accounts)
            accountRow(
                account,
                bucket: bucket,
                children: children,
                isChild: false
            )

            if !children.isEmpty && expandedMainAccountIDs.contains(account.id) {
                ForEach(children) { child in
                    accountRow(
                        child,
                        bucket: bucket,
                        children: [],
                        isChild: true
                    )
                }
            }
        }
    }

    private func accountRow(
        _ account: LedgerAccount,
        bucket: BalanceSheetBucket,
        children: [LedgerAccount],
        isChild: Bool
    ) -> some View {
        HStack(spacing: 5) {
            if !children.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        toggleMainAccount(account.id)
                    }
                } label: {
                    Image(systemName: expandedMainAccountIDs.contains(account.id)
                        ? "chevron.down"
                        : "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.purple)
                        .frame(width: 25, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(
                    expandedMainAccountIDs.contains(account.id)
                        ? "Collapse \(account.name) sub-accounts"
                        : "Expand \(account.name) sub-accounts"
                )
            } else {
                Color.clear
                    .frame(width: 25, height: 34)
            }

            NavigationLink {
                ChartLinkedTransactionsView(
                    title: account.name,
                    accountID: account.id,
                    category: nil,
                    type: nil
                )
                .environmentObject(store)
            } label: {
                ChartAccountRow(
                    account: account,
                    bucket: bucket,
                    parentName: store.account(withID: account.parentAccountID)?.name,
                    consolidatedTotals: store.consolidatedBalances(for: account),
                    subAccountCount: store.subAccounts(of: account.id).count
                )
                .environmentObject(store)
                .contentShape(Rectangle())
                .padding(.leading, isChild ? 6 : 0)
            }
            .buttonStyle(.plain)

            Button { editor = .account(account.id) } label: {
                Image(systemName: "pencil")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit \(account.name)")
        }
        .listRowInsets(EdgeInsets(
            top: 4,
            leading: isChild ? 28 : 16,
            bottom: 4,
            trailing: 16
        ))
        .listRowBackground(isChild ? AppTheme.purple.opacity(0.025) : Color.clear)
    }

    private func topLevelAccounts(in accounts: [LedgerAccount]) -> [LedgerAccount] {
        let ids = Set(accounts.map(\.id))
        return accounts.filter { account in
            guard let parentID = account.parentAccountID else { return true }
            return !ids.contains(parentID)
        }.sorted(by: accountSort)
    }

    private func childAccounts(
        of account: LedgerAccount,
        in accounts: [LedgerAccount]
    ) -> [LedgerAccount] {
        accounts.filter { $0.parentAccountID == account.id }
            .sorted(by: accountSort)
    }

    private func toggleMainAccount(_ accountID: UUID) {
        if expandedMainAccountIDs.contains(accountID) {
            expandedMainAccountIDs.remove(accountID)
        } else {
            expandedMainAccountIDs.insert(accountID)
        }
    }

''',
)

print("Added collapsed statement sections and collapsible main-account families in Chart of Accounts.")
