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
        details: String
    ) {
        let item = LedgerTransaction(
            type: type,
            amount: amount,
            date: date,
            category: category,
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
        var ledger = LedgerDiskStore.shared.load()
        ledger.transactions.removeAll { $0.id == transaction.id }
        do {
            try LedgerDiskStore.shared.save(ledger)
            reload()
        } catch {
            errorMessage = "The transaction could not be deleted."
        }
    }

    func update(_ transaction: LedgerTransaction) {
        var ledger = LedgerDiskStore.shared.load()
        guard let index = ledger.transactions.firstIndex(where: { $0.id == transaction.id }) else {
            errorMessage = "The original transaction could not be found."
            return
        }
        ledger.transactions[index] = transaction
        do {
            try LedgerDiskStore.shared.save(ledger)
            reload()
        } catch {
            errorMessage = "The transaction could not be updated."
        }
    }

    func updateCurrency(_ code: String) {
        guard code != settings.currencyCode else { return }
        var ledger = LedgerDiskStore.shared.load()
        ledger.settings.currencyCode = code
        do {
            try LedgerDiskStore.shared.save(ledger)
            reload()
        } catch {
            errorMessage = "The currency could not be updated."
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
        var ledger = LedgerDiskStore.shared.load()
        ledger.transactions = []
        do {
            try LedgerDiskStore.shared.save(ledger)
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

struct LedgerTotals {
    let income: Decimal
    let expense: Decimal
    let count: Int
    var balance: Decimal { income - expense }
}
