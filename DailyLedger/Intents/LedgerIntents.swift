import AppIntents
import Foundation

struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense"
    static let description = IntentDescription("Record an expense in Daily Ledger without opening the app.")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Category")
    var category: String?

    @Parameter(title: "Description")
    var details: String?

    @Parameter(title: "Date")
    var date: Date?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount.isFinite, amount > 0 else {
            return .result(dialog: "Enter an amount greater than zero.")
        }

        let transaction = LedgerTransaction(
            type: .expense,
            amount: Decimal(amount),
            date: date ?? Date(),
            category: normalizedCategory(category),
            details: details ?? ""
        )

        do {
            try LedgerDiskStore.shared.add(transaction)
            return .result(dialog: "Expense saved in Daily Ledger.")
        } catch {
            return .result(dialog: "The expense could not be saved.")
        }
    }
}

struct AddIncomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Income"
    static let description = IntentDescription("Record income in Daily Ledger without opening the app.")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Category")
    var category: String?

    @Parameter(title: "Description")
    var details: String?

    @Parameter(title: "Date")
    var date: Date?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount.isFinite, amount > 0 else {
            return .result(dialog: "Enter an amount greater than zero.")
        }

        let transaction = LedgerTransaction(
            type: .income,
            amount: Decimal(amount),
            date: date ?? Date(),
            category: normalizedCategory(category, fallback: "Salary"),
            details: details ?? ""
        )

        do {
            try LedgerDiskStore.shared.add(transaction)
            return .result(dialog: "Income saved in Daily Ledger.")
        } catch {
            return .result(dialog: "The income could not be saved.")
        }
    }
}

struct OpenAddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Add Expense"
    static let description = IntentDescription("Open Daily Ledger on the expense entry screen.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        ShortcutRouter.requestAdd(.expense)
        return .result()
    }
}

struct OpenAddIncomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Add Income"
    static let description = IntentDescription("Open Daily Ledger on the income entry screen.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        ShortcutRouter.requestAdd(.income)
        return .result()
    }
}

struct DailyLedgerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Add an expense in \(.applicationName)",
                "Record expense with \(.applicationName)"
            ],
            shortTitle: "Add Expense",
            systemImageName: "minus.circle.fill"
        )

        AppShortcut(
            intent: AddIncomeIntent(),
            phrases: [
                "Add income in \(.applicationName)",
                "Record income with \(.applicationName)"
            ],
            shortTitle: "Add Income",
            systemImageName: "plus.circle.fill"
        )

        AppShortcut(
            intent: OpenAddExpenseIntent(),
            phrases: ["Open expense entry in \(.applicationName)"],
            shortTitle: "Open Expense Entry",
            systemImageName: "square.and.pencil"
        )

        AppShortcut(
            intent: OpenAddIncomeIntent(),
            phrases: ["Open income entry in \(.applicationName)"],
            shortTitle: "Open Income Entry",
            systemImageName: "square.and.pencil"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .purple }
}

private func normalizedCategory(_ category: String?, fallback: String = "Other") -> String {
    let value = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? fallback : value
}
