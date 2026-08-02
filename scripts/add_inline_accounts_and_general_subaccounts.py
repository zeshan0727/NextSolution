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
        raise RuntimeError(f"Expected one match in {relative}, found {count}: {old[:140]!r}")
    write(relative, text.replace(old, new, 1))


# Add an optional one-level parent link. Existing saved accounts remain compatible
# because a missing optional Codable key decodes as nil.
model = "DailyLedger/Models/LedgerTransaction.swift"
replace_once(
    model,
    """    var nature: AccountNature?
    var chartCode: String?
    let createdAt: Date
""",
    """    var nature: AccountNature?
    var chartCode: String?
    var parentAccountID: UUID?
    let createdAt: Date
""",
)
replace_once(
    model,
    """        nature: AccountNature? = nil,
        chartCode: String? = nil,
        createdAt: Date = Date()
""",
    """        nature: AccountNature? = nil,
        chartCode: String? = nil,
        parentAccountID: UUID? = nil,
        createdAt: Date = Date()
""",
)
replace_once(
    model,
    """        self.nature = nature
        self.chartCode = chartCode
        self.createdAt = createdAt
""",
    """        self.nature = nature
        self.chartCode = chartCode
        self.parentAccountID = parentAccountID
        self.createdAt = createdAt
""",
)

# Archiving a main account archives its direct sub-accounts as well.
store = "DailyLedger/Services/LedgerStore.swift"
replace_once(
    store,
    """            guard let index = ledger.accounts.firstIndex(where: { $0.id == account.id }) else { return }
            ledger.accounts[index].isArchived = true
            if ledger.settings.defaultAccountID == account.id {
""",
    """            guard let index = ledger.accounts.firstIndex(where: { $0.id == account.id }) else { return }
            ledger.accounts[index].isArchived = true
            if ledger.accounts[index].parentAccountID == nil {
                for childIndex in ledger.accounts.indices
                where ledger.accounts[childIndex].parentAccountID == account.id {
                    ledger.accounts[childIndex].isArchived = true
                }
            }
            if ledger.settings.defaultAccountID == account.id {
""",
)

accounts_view = "DailyLedger/Views/AccountsView.swift"

# Show sub-account hierarchy in the Accounts screen.
replace_once(
    accounts_view,
    """                                    AccountRow(account: account, balance: store.balance(for: account))
""",
    """                                    AccountRow(
                                        account: account,
                                        balance: store.balance(for: account),
                                        parentName: store.account(withID: account.parentAccountID)?.name
                                    )
""",
)
replace_once(
    accounts_view,
    """    private func accounts(in group: AccountGroup) -> [LedgerAccount] {
        store.activeAccounts
            .filter {
                $0.group == group && (searchText.isEmpty ||
                    $0.name.localizedCaseInsensitiveContains(searchText) ||
                    $0.currencyCode.localizedCaseInsensitiveContains(searchText))
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
""",
    """    private func accounts(in group: AccountGroup) -> [LedgerAccount] {
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
        let included = Set(ordered.map(\\.id))
        ordered.append(contentsOf: matching.filter { !included.contains($0.id) }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })
        return ordered
    }
""",
)
replace_once(
    accounts_view,
    """private struct AccountRow: View {
    let account: LedgerAccount
    let balance: Decimal

    var body: some View {
        HStack(spacing: 13) {
""",
    """private struct AccountRow: View {
    let account: LedgerAccount
    let balance: Decimal
    let parentName: String?

    var body: some View {
        HStack(spacing: 13) {
""",
)
replace_once(
    accounts_view,
    """            VStack(alignment: .leading, spacing: 3) {
                Text(account.name)
                    .font(.body.weight(.semibold))
                Text(account.currencyCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
""",
    """            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if parentName != nil {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2.bold())
                            .foregroundStyle(AppTheme.purple)
                    }
                    Text(account.name)
                        .font(.body.weight(.semibold))
                }
                Text(parentName.map { "Sub-account of \\($0) · \\(account.currencyCode)" } ?? account.currencyCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
""",
)

# Expand AccountEditorView so it can be launched from transfers, return the new
# account, and assign any direct main account as parent.
replace_once(
    accounts_view,
    """    @State private var chartCode = ""
    private let account: LedgerAccount?

    private let currencies = ["QAR", "PKR", "USD", "GBP", "EUR", "AED", "SAR", "INR"]
""",
    """    @State private var chartCode = ""
    @State private var parentAccountID: UUID?
    private let account: LedgerAccount?
    private let onSaved: ((LedgerAccount) -> Void)?

    private let currencies = ["QAR", "PKR", "USD", "GBP", "EUR", "AED", "SAR", "INR"]
""",
)
replace_once(
    accounts_view,
    """    init(account: LedgerAccount? = nil) {
        self.account = account
        _name = State(initialValue: account?.name ?? "")
        _currencyCode = State(initialValue: account?.currencyCode ?? "QAR")
        _group = State(initialValue: account?.group ?? .qatar)
        _icon = State(initialValue: account?.icon ?? "creditcard.fill")
        _openingBalance = State(initialValue: account.map {
            NSDecimalNumber(decimal: $0.openingBalance).stringValue
        } ?? "0")
        _nature = State(initialValue: account?.nature ?? .unassigned)
        _chartCode = State(initialValue: account?.chartCode ?? "")
    }
""",
    """    init(
        account: LedgerAccount? = nil,
        initialGroup: AccountGroup? = nil,
        initialCurrency: String? = nil,
        initialParentAccountID: UUID? = nil,
        onSaved: ((LedgerAccount) -> Void)? = nil
    ) {
        self.account = account
        self.onSaved = onSaved
        _name = State(initialValue: account?.name ?? "")
        _currencyCode = State(initialValue: account?.currencyCode ?? initialCurrency ?? "QAR")
        _group = State(initialValue: account?.group ?? initialGroup ?? .qatar)
        _icon = State(initialValue: account?.icon ?? "creditcard.fill")
        _openingBalance = State(initialValue: account.map {
            NSDecimalNumber(decimal: $0.openingBalance).stringValue
        } ?? "0")
        _nature = State(initialValue: account?.nature ?? .unassigned)
        _chartCode = State(initialValue: account?.chartCode ?? "")
        _parentAccountID = State(initialValue: account?.parentAccountID ?? initialParentAccountID)
    }
""",
)
replace_once(
    accounts_view,
    """                    Picker("Group", selection: $group) {
                        ForEach(AccountGroup.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Account Nature", selection: $nature) {
""",
    """                    Picker("Group", selection: $group) {
                        ForEach(AccountGroup.allCases) { Text($0.title).tag($0) }
                    }
                    .disabled(parentAccountID != nil)
                    Picker("Parent Account", selection: $parentAccountID) {
                        Text("Main Account (No Parent)").tag(Optional<UUID>.none)
                        ForEach(parentCandidates) { candidate in
                            Text("\\(candidate.name) · \\(candidate.group.title)")
                                .tag(Optional(candidate.id))
                        }
                    }
                    .disabled(hasSubAccounts)
                    if hasSubAccounts {
                        Text("This account already has sub-accounts, so it must remain a main account.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let parent = selectedParent {
                        Text("This sub-account will appear under \\(parent.name). Its currency and opening balance remain independent.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Picker("Account Nature", selection: $nature) {
""",
)
replace_once(
    accounts_view,
    """            .navigationTitle(account == nil ? "New Account" : "Edit Account")
""",
    """            .navigationTitle(account == nil ? "New Account" : "Edit Account")
            .onChange(of: parentAccountID) { _ in
                if let parent = selectedParent {
                    group = parent.group
                }
            }
""",
)
replace_once(
    accounts_view,
    """    private var cleanedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var parsedOpeningBalance: Decimal? {
""",
    """    private var cleanedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var parentCandidates: [LedgerAccount] {
        store.activeAccounts.filter {
            $0.parentAccountID == nil && $0.id != account?.id
        }.sorted {
            if $0.group != $1.group { return $0.group.title < $1.group.title }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var selectedParent: LedgerAccount? {
        store.account(withID: parentAccountID)
    }

    private var hasSubAccounts: Bool {
        guard let account else { return false }
        return store.accounts.contains { $0.parentAccountID == account.id }
    }

    private var parsedOpeningBalance: Decimal? {
""",
)
replace_once(
    accounts_view,
    """            account.nature = nature == .unassigned ? nil : nature
            account.chartCode = cleanedChartCode.nilIfEmpty
            store.updateAccount(account)
        } else {
            store.addAccount(LedgerAccount(
                name: cleanedName,
                currencyCode: currencyCode,
                group: group,
                icon: icon,
                openingBalance: balance,
                nature: nature == .unassigned ? nil : nature,
                chartCode: cleanedChartCode.nilIfEmpty
            ))
        }
        dismiss()
""",
    """            account.nature = nature == .unassigned ? nil : nature
            account.chartCode = cleanedChartCode.nilIfEmpty
            account.parentAccountID = hasSubAccounts ? nil : parentAccountID
            if let parent = store.account(withID: account.parentAccountID) {
                account.group = parent.group
            }
            store.updateAccount(account)
            onSaved?(account)
        } else {
            var newAccount = LedgerAccount(
                name: cleanedName,
                currencyCode: currencyCode,
                group: group,
                icon: icon,
                openingBalance: balance,
                nature: nature == .unassigned ? nil : nature,
                chartCode: cleanedChartCode.nilIfEmpty,
                parentAccountID: parentAccountID
            )
            if let parent = store.account(withID: parentAccountID) {
                newAccount.group = parent.group
            }
            store.addAccount(newAccount)
            onSaved?(newAccount)
        }
        dismiss()
""",
)

# Patch the generated transfer screen: expose standard currencies even when no
# account exists, provide Add Account for both sides, and select the result.
transfer = "DailyLedger/Views/TransferView.swift"
replace_once(
    transfer,
    """import Foundation
import SwiftUI

struct TransferView: View {
""",
    """import Foundation
import SwiftUI

private enum TransferAccountRole: String, Identifiable {
    case source
    case destination

    var id: String { rawValue }
    var title: String { self == .source ? "Source" : "Destination" }
}

struct TransferView: View {
""",
)
replace_once(
    transfer,
    """    @State private var details = ""
    @FocusState private var focusedAmount: AmountField?
""",
    """    @State private var details = ""
    @State private var addingAccountFor: TransferAccountRole?
    @FocusState private var focusedAmount: AmountField?
""",
)
replace_once(
    transfer,
    """                    accountPicker(
                        "Source Account",
                        selection: $sourceAccountID,
                        currency: sourceCurrencySelection
                    )
                    amountField("Amount Sent", text: $amountText, currency: sourceCurrency)
""",
    """                    accountPicker(
                        "Source Account",
                        selection: $sourceAccountID,
                        currency: sourceCurrencySelection
                    )
                    accountAvailabilityMessage(for: .source)
                    addAccountButton(for: .source)
                    amountField("Amount Sent", text: $amountText, currency: sourceCurrency)
""",
)
replace_once(
    transfer,
    """                    accountPicker(
                        "Destination Account",
                        selection: $destinationAccountID,
                        currency: destinationCurrencySelection
                    )
                    if !isCrossCurrency, let receivedAmount {
""",
    """                    accountPicker(
                        "Destination Account",
                        selection: $destinationAccountID,
                        currency: destinationCurrencySelection
                    )
                    accountAvailabilityMessage(for: .destination)
                    addAccountButton(for: .destination)
                    if !isCrossCurrency, let receivedAmount {
""",
)
replace_once(
    transfer,
    """            .onChange(of: destinationCurrencySelection) { value in
                selectDestinationAccount(for: value)
                configureConversion(preserveEditingRate: false)
            }
        }
    }
""",
    """            .onChange(of: destinationCurrencySelection) { value in
                selectDestinationAccount(for: value)
                configureConversion(preserveEditingRate: false)
            }
            .sheet(item: $addingAccountFor) { role in
                AccountEditorView(
                    initialGroup: .other,
                    initialCurrency: role == .source
                        ? normalizedCurrency(sourceCurrencySelection)
                        : normalizedCurrency(destinationCurrencySelection)
                ) { account in
                    selectNewAccount(account, for: role)
                }
                .environmentObject(store)
            }
        }
    }
""",
)
replace_once(
    transfer,
    """        Picker(title, selection: selection) {
            ForEach(filteredAccounts(currency: currency)) { account in
                Text(account.name)
                    .tag(Optional(account.id))
            }
        }
    }
""",
    """        Picker(title, selection: selection) {
            Text("Select Account").tag(Optional<UUID>.none)
            ForEach(filteredAccounts(currency: currency)) { account in
                Text(accountDisplayName(account))
                    .tag(Optional(account.id))
            }
        }
    }

    @ViewBuilder
    private func accountAvailabilityMessage(for role: TransferAccountRole) -> some View {
        let currency = role == .source ? sourceCurrencySelection : destinationCurrencySelection
        if filteredAccounts(currency: currency).isEmpty {
            Label(
                "No \\(normalizedCurrency(currency)) account is available.",
                systemImage: "exclamationmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func addAccountButton(for role: TransferAccountRole) -> some View {
        Button {
            addingAccountFor = role
        } label: {
            Label("Add \\(role.title) Account", systemImage: "plus.circle.fill")
        }
    }
""",
)
replace_once(
    transfer,
    """    private var availableCurrencies: [String] {
        Array(Set(store.activeAccounts.map { $0.currencyCode.uppercased() })).sorted()
    }
""",
    """    private var availableCurrencies: [String] {
        let standard = ["QAR", "PKR", "USD", "GBP", "EUR", "AED", "SAR", "INR"]
        return Array(Set(standard + store.activeAccounts.map { $0.currencyCode.uppercased() })).sorted()
    }
""",
)
replace_once(
    transfer,
    """    private var sourceAccount: LedgerAccount? {
""",
    """    private func accountDisplayName(_ account: LedgerAccount) -> String {
        if let parent = store.account(withID: account.parentAccountID) {
            return "↳ \\(parent.name) / \\(account.name)"
        }
        return account.name
    }

    private func normalizedCurrency(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return cleaned.isEmpty ? "QAR" : cleaned
    }

    private func selectNewAccount(_ account: LedgerAccount, for role: TransferAccountRole) {
        let currency = account.currencyCode.uppercased()
        if role == .source {
            sourceCurrencySelection = currency
            sourceAccountID = account.id
            if destinationAccountID == account.id {
                destinationAccountID = filteredAccounts(currency: destinationCurrencySelection)
                    .first(where: { $0.id != account.id })?.id
            }
        } else {
            destinationCurrencySelection = currency
            destinationAccountID = account.id
            if sourceAccountID == account.id {
                sourceAccountID = filteredAccounts(currency: sourceCurrencySelection)
                    .first(where: { $0.id != account.id })?.id
            }
        }
        configureConversion(preserveEditingRate: false)
    }

    private var sourceAccount: LedgerAccount? {
""",
)

print("Added inline transfer account creation and one-level sub-accounts for every main account.")
