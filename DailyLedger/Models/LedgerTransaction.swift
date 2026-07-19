import Foundation

enum TransactionType: String, Codable, CaseIterable, Identifiable {
    case income
    case expense

    var id: String { rawValue }

    var title: String {
        switch self {
        case .income: return "Income"
        case .expense: return "Expense"
        }
    }
}

struct LedgerTransaction: Identifiable, Codable, Hashable {
    let id: UUID
    var type: TransactionType
    var amount: Decimal
    var date: Date
    var category: String
    var details: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        type: TransactionType,
        amount: Decimal,
        date: Date = Date(),
        category: String,
        details: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.date = date
        self.category = category
        self.details = details
        self.createdAt = createdAt
    }
}

struct LedgerSettings: Codable, Equatable {
    var currencyCode: String = "QAR"
}

struct LedgerData: Codable {
    var version: Int = 1
    var transactions: [LedgerTransaction] = []
    var settings = LedgerSettings()
}

extension LedgerTransaction {
    static let expenseCategories = [
        "Food", "Shopping", "Transport", "Bills", "Fuel",
        "Health", "Home", "Family", "Entertainment", "Other"
    ]

    static let incomeCategories = [
        "Salary", "Business", "Refund", "Gift", "Investment", "Other"
    ]
}

