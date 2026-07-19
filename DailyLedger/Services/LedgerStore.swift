import Combine
import Foundation

@MainActor
final class LedgerStore: ObservableObject {
    @Published private(set) var transactions: [LedgerTransaction] = []
    @Published private(set) var settings = LedgerSettings()
    @Published var errorMessage: String?

    init() {
        reload()
    }

    var currencyCode: String { settings.currencyCode }

    func reload() {
        let ledger = LedgerDiskStore.shared.load()
        transactions = ledger.transactions.sorted { $0.date > $1.date }
        settings = ledger.settings
    }

    func add(
        type: TransactionType,
        amount: Decimal,
        date: Date,
        category: String,
        vendor: String = "",
        details: String
    ) {
        let item = LedgerTransaction(
            type: type,
            amount: amount,
            date: date,
            category: category,
            vendor: vendor.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            details: details.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            try LedgerDiskStore.shared.add(item)
            reload()
        } catch {
            errorMessage = "The transaction could not be saved."
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

    func importFile(at url: URL) throws -> Int {
        let incoming = try ImportExportCodec.decode(url: url)
        let oldCount = LedgerDiskStore.shared.load().transactions.count
        let ledger = try LedgerDiskStore.shared.merge(
            incoming.transactions,
            restoring: incoming.settings
        )
        reload()
        return ledger.transactions.count - oldCount
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

    func totals(in interval: DateInterval) -> LedgerTotals {
        let selected = transactions.filter { interval.contains($0.date) }
        let income = selected
            .filter { $0.type == .income }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let expense = selected
            .filter { $0.type == .expense }
            .reduce(Decimal.zero) { $0 + $1.amount }
        return LedgerTotals(income: income, expense: expense, count: selected.count)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct LedgerTotals {
    let income: Decimal
    let expense: Decimal
    let count: Int
    var balance: Decimal { income - expense }
}
