import Combine
import Foundation

@MainActor
final class LedgerStore: ObservableObject {
    @Published private(set) var transactions: [LedgerTransaction] = []
    @Published private(set) var accounts: [LedgerAccount] = []
    @Published private(set) var settings = LedgerSettings()
    @Published var errorMessage: String?

    init() {
        importBundledPersonalSeedIfNeeded()
        reload()
    }

    private func importBundledPersonalSeedIfNeeded() {
        let key = "DailyLedgerPersonalSeedImported"
        guard !UserDefaults.standard.bool(forKey: key),
              let url = Bundle.main.url(forResource: "PersonalLedgerSeed", withExtension: "json"),
              let incoming = try? ImportExportCodec.decode(url: url) else { return }
        do {
            try LedgerDiskStore.shared.merge(
                incoming.transactions,
                accounts: incoming.accounts,
                restoring: incoming.settings
            )
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            errorMessage = "The bundled personal ledger could not be loaded."
        }
    }

    var currencyCode: String { settings.currencyCode }
    var defaultAccountID: UUID? { settings.defaultAccountID ?? accounts.first?.id }
    var activeAccounts: [LedgerAccount] { accounts.filter { !$0.isArchived } }

    func reload() {
        let ledger = LedgerDiskStore.shared.load()
        transactions = ledger.transactions.sorted { $0.date > $1.date }
        accounts = ledger.accounts
        settings = ledger.settings
    }

    func add(
        type: TransactionType,
        amount: Decimal,
        date: Date,
        category: String,
        vendor: String = "",
        details: String,
        accountID: UUID? = nil
    ) {
        let item = LedgerTransaction(
            type: type,
            amount: amount,
            date: date,
            category: category,
            vendor: vendor.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            accountID: accountID ?? defaultAccountID
        )
        do {
            try LedgerDiskStore.shared.add(item)
            reload()
        } catch {
            errorMessage = "The transaction could not be saved."
        }
    }

    func addTransfer(
        from sourceID: UUID,
        to destinationID: UUID,
        amount: Decimal,
        destinationAmount: Decimal,
        date: Date,
        details: String
    ) {
        guard sourceID != destinationID else {
            errorMessage = "Choose two different accounts."
            return
        }
        let item = LedgerTransaction(
            type: .transfer,
            amount: amount,
            date: date,
            category: "Transfer",
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            accountID: sourceID,
            destinationAccountID: destinationID,
            destinationAmount: destinationAmount
        )
        do {
            try LedgerDiskStore.shared.add(item)
            reload()
        } catch {
            errorMessage = "The transfer could not be saved."
        }
    }

    func addAccount(_ account: LedgerAccount) {
        updateLedger(failureMessage: "The account could not be saved.") { ledger in
            guard !ledger.accounts.contains(where: { $0.id == account.id }) else { return }
            ledger.accounts.append(account)
            if ledger.settings.defaultAccountID == nil {
                ledger.settings.defaultAccountID = account.id
            }
        }
    }

    func updateAccount(_ account: LedgerAccount) {
        updateLedger(failureMessage: "The account could not be updated.") { ledger in
            guard let index = ledger.accounts.firstIndex(where: { $0.id == account.id }) else { return }
            ledger.accounts[index] = account
        }
    }

    func archiveAccount(_ account: LedgerAccount) {
        updateLedger(failureMessage: "The account could not be archived.") { ledger in
            guard let index = ledger.accounts.firstIndex(where: { $0.id == account.id }) else { return }
            ledger.accounts[index].isArchived = true
            if ledger.settings.defaultAccountID == account.id {
                ledger.settings.defaultAccountID = ledger.accounts.first(where: { !$0.isArchived })?.id
            }
        }
    }

    func account(withID id: UUID?) -> LedgerAccount? {
        guard let id else { return nil }
        return accounts.first(where: { $0.id == id })
    }

    func balance(for account: LedgerAccount) -> Decimal {
        transactions.reduce(account.openingBalance) { result, item in
            switch item.type {
            case .income where item.accountID == account.id:
                return result + item.amount
            case .expense where item.accountID == account.id:
                return result - item.amount
            case .transfer where item.accountID == account.id:
                return result - item.amount
            case .transfer where item.destinationAccountID == account.id:
                return result + (item.destinationAmount ?? item.amount)
            default:
                return result
            }
        }
    }

    func delete(_ transaction: LedgerTransaction) {
        do {
            try LedgerDiskStore.shared.mutate { ledger in
                ledger.transactions.removeAll { $0.id == transaction.id }
            }
            reload()
        } catch {
            errorMessage = "The transaction could not be deleted."
        }
    }

    func update(_ transaction: LedgerTransaction) {
        var found = false
        do {
            try LedgerDiskStore.shared.mutate { ledger in
                guard let index = ledger.transactions.firstIndex(where: { $0.id == transaction.id }) else {
                    return
                }
                ledger.transactions[index] = transaction
                found = true
            }
            guard found else {
                errorMessage = "The original transaction could not be found."
                return
            }
            reload()
        } catch {
            errorMessage = "The transaction could not be updated."
        }
    }

    func updateCurrency(_ code: String) {
        guard code != settings.currencyCode else { return }
        updateLedger(failureMessage: "The currency could not be updated.") { ledger in
            ledger.settings.currencyCode = code
        }
    }

    func updateSMSAutoImport(_ enabled: Bool) {
        guard enabled != settings.smsAutoImportEnabled else { return }
        updateLedger(failureMessage: "The SMS auto-import setting could not be updated.") { ledger in
            ledger.settings.smsAutoImportEnabled = enabled
        }
    }

    func updateSMSPreferences(matchText: String, destinationAccountID: UUID?) {
        updateLedger(failureMessage: "The SMS import preferences could not be updated.") { ledger in
            ledger.settings.smsMatchText = matchText.trimmingCharacters(in: .whitespacesAndNewlines)
            ledger.settings.smsDestinationAccountID = destinationAccountID
        }
    }

    func requestSMSRescan() {
        updateLedger(failureMessage: "The SMS rescan could not be requested.") { ledger in
            ledger.settings.smsRescanRequestID += 1
        }
    }

    func saveVendorRule(_ rule: VendorCategoryRule) {
        updateLedger(failureMessage: "The vendor rule could not be saved.") { ledger in
            if let index = ledger.settings.vendorRules.firstIndex(where: { $0.id == rule.id }) {
                ledger.settings.vendorRules[index] = rule
            } else {
                ledger.settings.vendorRules.append(rule)
            }
        }
    }

    func deleteVendorRules(at offsets: IndexSet) {
        updateLedger(failureMessage: "The vendor rule could not be deleted.") { ledger in
            for index in offsets.sorted(by: >) where ledger.settings.vendorRules.indices.contains(index) {
                ledger.settings.vendorRules.remove(at: index)
            }
        }
    }

    func resetVendorRules() {
        updateLedger(failureMessage: "The vendor rules could not be reset.") { ledger in
            ledger.settings.vendorRules = VendorCategoryRule.defaults
        }
    }

    var uncategorizedTransactions: [LedgerTransaction] {
        let now = Date()
        return transactions.filter { isAutoCategorizationCandidate($0, now: now) }
    }

    @discardableResult
    func automaticallyCategorizeTransactions() -> CategorizationSummary {
        var categorized = 0
        let now = Date()
        updateLedger(failureMessage: "Transactions could not be categorized.") { ledger in
            let rules = (ledger.settings.vendorRules + VendorCategoryRule.defaults).sorted {
                $0.keyword.count > $1.keyword.count
            }
            for index in ledger.transactions.indices {
                let transaction = ledger.transactions[index]
                guard isAutoCategorizationCandidate(transaction, now: now),
                      let category = suggestedCategory(for: transaction, rules: rules) else { continue }
                ledger.transactions[index].category = category
                categorized += 1
            }
        }
        return CategorizationSummary(
            categorizedCount: categorized,
            reviewCount: uncategorizedTransactions.count
        )
    }

    func suggestedCategory(for transaction: LedgerTransaction) -> String? {
        suggestedCategory(for: transaction, rules: settings.vendorRules)
    }

    private func suggestedCategory(
        for transaction: LedgerTransaction,
        rules: [VendorCategoryRule]
    ) -> String? {
        let text = [transaction.vendor, transaction.details]
            .compactMap { $0 }
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        guard !text.isEmpty else { return nil }
        return rules.first { rule in
            let keyword = rule.keyword
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
            return !keyword.isEmpty && text.contains(keyword)
        }?.category
    }

    private func isAutoCategorizationCandidate(
        _ transaction: LedgerTransaction,
        now: Date
    ) -> Bool {
        guard transaction.type != .transfer else { return false }
        let categoryMatches = transaction.category
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Z-iP-14PM-16.0") == .orderedSame
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now)
            ?? now.addingTimeInterval(-30 * 24 * 60 * 60)
        return categoryMatches && transaction.date >= cutoff && transaction.date <= now
    }

    private func updateLedger(
        failureMessage: String,
        _ changes: (inout LedgerData) -> Void
    ) {
        do {
            try LedgerDiskStore.shared.mutate(changes)
            reload()
        } catch {
            errorMessage = failureMessage
        }
    }

    func importFile(at url: URL) throws -> ImportSummary {
        let incoming = try ImportExportCodec.decode(url: url)
        let oldLedger = LedgerDiskStore.shared.load()
        let ledger = try LedgerDiskStore.shared.merge(
            incoming.transactions,
            accounts: incoming.accounts,
            restoring: incoming.settings
        )
        reload()
        return ImportSummary(
            transactionCount: ledger.transactions.count - oldLedger.transactions.count,
            accountCount: ledger.accounts.count - oldLedger.accounts.count
        )
    }

    func deleteAll() {
        do {
            try LedgerDiskStore.shared.mutate { ledger in
                ledger.transactions = []
            }
            reload()
        } catch {
            errorMessage = "The data could not be deleted."
        }
    }

    func syncBackupNow() {
        BackupSyncService.shared.syncNow(ledger: LedgerDiskStore.shared.load())
    }

    func restoreLatestICloudBackup() {
        do {
            let ledger = try BackupSyncService.shared.restoreLatestICloudBackup()
            try LedgerDiskStore.shared.save(ledger)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func categories(for type: TransactionType) -> [String] {
        let defaults = type == .expense
            ? LedgerTransaction.expenseCategories
            : LedgerTransaction.incomeCategories
        let used = transactions
            .filter { $0.type == type }
            .map(\.category)
        return (defaults + used).reduce(into: [String]()) { result, item in
            let cleaned = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty && !result.contains(where: {
                $0.caseInsensitiveCompare(cleaned) == .orderedSame
            }) {
                result.append(cleaned)
            }
        }
    }

    func totals(in interval: DateInterval) -> LedgerTotals {
        let selected = transactions.filter {
            interval.contains($0.date) && account(withID: $0.accountID)?.currencyCode == currencyCode
        }
        let income = selected
            .filter { $0.type == .income }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let expense = selected
            .filter { $0.type == .expense }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let loan = selected
            .filter {
                $0.type == .transfer &&
                account(withID: $0.destinationAccountID)?.group == .payments
            }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let transfer = selected
            .filter { $0.type == .transfer }
            .reduce(Decimal.zero) { $0 + $1.amount }
        return LedgerTotals(
            income: income,
            expense: expense,
            loan: loan,
            transfer: transfer,
            count: selected.count
        )
    }
}

struct ImportSummary {
    let transactionCount: Int
    let accountCount: Int
}

struct CategorizationSummary {
    let categorizedCount: Int
    let reviewCount: Int
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct LedgerTotals {
    let income: Decimal
    let expense: Decimal
    let loan: Decimal
    let transfer: Decimal
    let count: Int
    var balance: Decimal { income - expense - transfer }
}
