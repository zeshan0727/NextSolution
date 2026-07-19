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
    var vendor: String?
    var details: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        type: TransactionType,
        amount: Decimal,
        date: Date = Date(),
        category: String,
        vendor: String? = nil,
        details: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.date = date
        self.category = category
        self.vendor = vendor
        self.details = details
        self.createdAt = createdAt
    }
}

struct VendorCategoryRule: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var keyword: String
    var category: String

    init(id: UUID = UUID(), keyword: String, category: String) {
        self.id = id
        self.keyword = keyword
        self.category = category
    }

    static let defaults: [VendorCategoryRule] = [
        VendorCategoryRule(keyword: "restaurant", category: "Restaurant"),
        VendorCategoryRule(keyword: "cafe", category: "Restaurant"),
        VendorCategoryRule(keyword: "coffee", category: "Restaurant"),
        VendorCategoryRule(keyword: "grocery", category: "Grocery"),
        VendorCategoryRule(keyword: "supermarket", category: "Grocery"),
        VendorCategoryRule(keyword: "hypermarket", category: "Grocery"),
        VendorCategoryRule(keyword: "woqod", category: "Fuel"),
        VendorCategoryRule(keyword: "petrol", category: "Fuel"),
        VendorCategoryRule(keyword: "fuel", category: "Fuel"),
        VendorCategoryRule(keyword: "uber", category: "Transport"),
        VendorCategoryRule(keyword: "karwa", category: "Transport"),
        VendorCategoryRule(keyword: "taxi", category: "Transport"),
        VendorCategoryRule(keyword: "pharmacy", category: "Health"),
        VendorCategoryRule(keyword: "clinic", category: "Health"),
        VendorCategoryRule(keyword: "hospital", category: "Health")
    ]
}

struct LedgerSettings: Codable, Equatable {
    var currencyCode: String
    var vendorRules: [VendorCategoryRule]
    var smsAutoImportEnabled: Bool

    init(
        currencyCode: String = "QAR",
        vendorRules: [VendorCategoryRule] = VendorCategoryRule.defaults,
        smsAutoImportEnabled: Bool = true
    ) {
        self.currencyCode = currencyCode
        self.vendorRules = vendorRules
        self.smsAutoImportEnabled = smsAutoImportEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case currencyCode
        case vendorRules
        case smsAutoImportEnabled
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        currencyCode = try values.decodeIfPresent(String.self, forKey: .currencyCode) ?? "QAR"
        vendorRules = try values.decodeIfPresent([VendorCategoryRule].self, forKey: .vendorRules)
            ?? VendorCategoryRule.defaults
        smsAutoImportEnabled = try values.decodeIfPresent(Bool.self, forKey: .smsAutoImportEnabled) ?? true
    }
}

struct LedgerData: Codable {
    var version: Int = 2
    var transactions: [LedgerTransaction] = []
    var settings = LedgerSettings()
}

extension LedgerTransaction {
    static let expenseCategories = [
        "Restaurant", "Grocery", "Food", "Shopping", "Transport", "Bills", "Fuel",
        "Health", "Home", "Family", "Entertainment", "Other"
    ]

    static let incomeCategories = [
        "Salary", "Business", "Refund", "Gift", "Investment", "Other"
    ]
}
