import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var editingAccount: LedgerAccount?
    @State private var addingAccount = false
    @State private var showingTransfer = false
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingTransfer = true
                    } label: {
                        Label("Transfer Between Accounts", systemImage: "arrow.left.arrow.right.circle.fill")
                            .font(.headline)
                            .foregroundStyle(AppTheme.purple)
                    }
                    .disabled(store.activeAccounts.count < 2)
                }

                ForEach(AccountGroup.allCases) { group in
                    let accounts = accounts(in: group)
                    if !accounts.isEmpty {
                        Section(group.title.uppercased()) {
                            ForEach(accounts) { account in
                                NavigationLink {
                                    AccountDetailView(accountID: account.id)
                                } label: {
                                    AccountRow(account: account, balance: store.balance(for: account))
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
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Accounts")
            .searchable(text: $searchText, prompt: "Search accounts")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { addingAccount = true } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add account")
                }
            }
            .sheet(isPresented: $addingAccount) {
                AccountEditorView()
                    .environmentObject(store)
            }
            .sheet(item: $editingAccount) { account in
                AccountEditorView(account: account)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showingTransfer) {
                TransferView()
                    .environmentObject(store)
            }
        }
    }

    private func accounts(in group: AccountGroup) -> [LedgerAccount] {
        store.activeAccounts
            .filter {
                $0.group == group && (searchText.isEmpty ||
                    $0.name.localizedCaseInsensitiveContains(searchText) ||
                    $0.currencyCode.localizedCaseInsensitiveContains(searchText))
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private struct AccountRow: View {
    let account: LedgerAccount
    let balance: Decimal

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: account.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.blue)
                .frame(width: 40, height: 40)
                .background(AppTheme.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(account.name)
                    .font(.body.weight(.semibold))
                Text(account.currencyCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(DisplayFormat.currency(balance, code: account.currencyCode))
                .font(.subheadline.bold())
                .foregroundStyle(balance < 0 ? AppTheme.red : .primary)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

private struct AccountDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    let accountID: UUID
    @State private var editingTransaction: LedgerTransaction?
    @State private var addingExpense = false
    @State private var addingIncome = false
    @State private var transferring = false
    @State private var searchText = ""

    var body: some View {
        List {
            if let account {
                Section {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("CURRENT BALANCE")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                        Text(DisplayFormat.currency(store.balance(for: account), code: account.currencyCode))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(AppTheme.balanceGradient, in: RoundedRectangle(cornerRadius: 20))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section("Actions") {
                    Button { addingExpense = true } label: {
                        Label("Add Expense", systemImage: "minus.circle.fill")
                    }
                    Button { addingIncome = true } label: {
                        Label("Add Income", systemImage: "plus.circle.fill")
                    }
                    Button { transferring = true } label: {
                        Label("Transfer", systemImage: "arrow.left.arrow.right.circle.fill")
                    }
                }
            }

            Section("Transactions") {
                if transactions.isEmpty {
                    Text("No transactions in this account.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(transactions) { transaction in
                        Button { editingTransaction = transaction } label: {
                            TransactionRow(transaction: transaction)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(account?.name ?? "Account")
        .searchable(text: $searchText, prompt: "Search transactions")
        .sheet(isPresented: $addingExpense) {
            AddTransactionView(initialType: .expense, accountID: accountID)
                .environmentObject(store)
        }
        .sheet(isPresented: $addingIncome) {
            AddTransactionView(initialType: .income, accountID: accountID)
                .environmentObject(store)
        }
        .sheet(isPresented: $transferring) {
            TransferView(sourceAccountID: accountID)
                .environmentObject(store)
        }
        .sheet(item: $editingTransaction) { transaction in
            if transaction.type == .transfer {
                TransferView(transaction: transaction)
                    .environmentObject(store)
            } else {
                AddTransactionView(transaction: transaction)
                    .environmentObject(store)
            }
        }
    }

    private var account: LedgerAccount? { store.account(withID: accountID) }

    private var transactions: [LedgerTransaction] {
        store.transactions.filter {
            let belongs = $0.accountID == accountID || $0.destinationAccountID == accountID
            guard belongs, !searchText.isEmpty else { return belongs }
            return $0.category.localizedCaseInsensitiveContains(searchText) ||
                ($0.vendor?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                $0.details.localizedCaseInsensitiveContains(searchText) ||
                NSDecimalNumber(decimal: $0.amount).stringValue.contains(searchText)
        }
    }
}

private struct AccountEditorView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var currencyCode = "QAR"
    @State private var group: AccountGroup = .qatar
    @State private var icon = "creditcard.fill"
    @State private var openingBalance = "0"
    private let account: LedgerAccount?

    private let currencies = ["QAR", "PKR", "USD", "GBP", "EUR", "AED", "SAR", "INR"]
    private let icons = ["creditcard.fill", "banknote.fill", "wallet.pass.fill", "building.columns.fill", "car.fill", "house.fill", "person.2.fill", "iphone.gen3"]

    init(account: LedgerAccount? = nil) {
        self.account = account
        _name = State(initialValue: account?.name ?? "")
        _currencyCode = State(initialValue: account?.currencyCode ?? "QAR")
        _group = State(initialValue: account?.group ?? .qatar)
        _icon = State(initialValue: account?.icon ?? "creditcard.fill")
        _openingBalance = State(initialValue: account.map {
            NSDecimalNumber(decimal: $0.openingBalance).stringValue
        } ?? "0")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Name", text: $name)
                    Picker("Currency", selection: $currencyCode) {
                        ForEach(currencies, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Group", selection: $group) {
                        ForEach(AccountGroup.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Icon", selection: $icon) {
                        ForEach(icons, id: \.self) { value in
                            Label(value.replacingOccurrences(of: ".fill", with: ""), systemImage: value)
                                .tag(value)
                        }
                    }
                    TextField("Opening balance", text: $openingBalance)
                        .keyboardType(.numbersAndPunctuation)
                }

                if let account {
                    Section {
                        Button("Archive Account", role: .destructive) {
                            store.archiveAccount(account)
                            dismiss()
                        }
                    } footer: {
                        Text("Existing transactions remain available after archiving.")
                    }
                }
            }
            .navigationTitle(account == nil ? "New Account" : "Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(cleanedName.isEmpty || parsedOpeningBalance == nil)
                }
            }
        }
    }

    private var cleanedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var parsedOpeningBalance: Decimal? {
        Decimal(
            string: openingBalance.replacingOccurrences(of: ",", with: ""),
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private func save() {
        guard let balance = parsedOpeningBalance else { return }
        if var account {
            account.name = cleanedName
            account.currencyCode = currencyCode
            account.group = group
            account.icon = icon
            account.openingBalance = balance
            store.updateAccount(account)
        } else {
            store.addAccount(LedgerAccount(
                name: cleanedName,
                currencyCode: currencyCode,
                group: group,
                icon: icon,
                openingBalance: balance
            ))
        }
        dismiss()
    }
}
