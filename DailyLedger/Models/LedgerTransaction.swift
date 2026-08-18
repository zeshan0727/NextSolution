import Foundation

enum TransactionType: String, Codable, CaseIterable, Identifiable {
    case income
    case expense
    case transfer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .income: return "Income"
        case .expense: return "Expense"
        case .transfer: return "Transfer"
        }
    }
}

enum AccountGroup: String, Codable, CaseIterable, Identifiable {
    case qatar
    case pakistan
    case payments
    case assets
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qatar: return "Qatar"
        case .pakistan: return "Pakistan"
        case .payments: return "Payments"
        case .assets: return "Assets"
        case .other: return "Other"
        }
    }
}

enum AccountNature: String, Codable, CaseIterable, Identifiable {
    case unassigned
    case loan
    case control
    case asset
    case dailyExpense
    case bank

    var id: String { rawValue }
    var title: String {
        switch self {
        case .unassigned: return "Unassigned"
        case .loan: return "Loan"
        case .control: return "Control"
        case .asset: return "Asset"
        case .dailyExpense: return "Daily Expense"
        case .bank: return "Bank"
        }
    }
}

struct LedgerAccount: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var currencyCode: String
    var group: AccountGroup
    var icon: String
    var openingBalance: Decimal
    var isArchived: Bool
    var nature: AccountNature?
    var chartCode: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        currencyCode: String = "QAR",
        group: AccountGroup = .qatar,
        icon: String = "creditcard.fill",
        openingBalance: Decimal = 0,
        isArchived: Bool = false,
        nature: AccountNature? = nil,
        chartCode: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.currencyCode = currencyCode
        self.group = group
        self.icon = icon
        self.openingBalance = openingBalance
        self.isArchived = isArchived
        self.nature = nature
        self.chartCode = chartCode
        self.createdAt = createdAt
    }

    static let legacyMainID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let legacyMain = LedgerAccount(
        id: legacyMainID,
        name: "Main Account",
        currencyCode: "QAR",
        group: .qatar,
        icon: "wallet.pass.fill"
    )
}

struct LedgerTransaction: Identifiable, Codable, Hashable {
    let id: UUID
    var type: TransactionType
    var amount: Decimal
    var date: Date
    var category: String
    var vendor: String?
    var details: String
    var accountID: UUID?
    var destinationAccountID: UUID?
    var destinationAmount: Decimal?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        type: TransactionType,
        amount: Decimal,
        date: Date = Date(),
        category: String,
        vendor: String? = nil,
        details: String = "",
        accountID: UUID? = nil,
        destinationAccountID: UUID? = nil,
        destinationAmount: Decimal? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.date = date
        self.category = category
        self.vendor = vendor
        self.details = details
        self.accountID = accountID
        self.destinationAccountID = destinationAccountID
        self.destinationAmount = destinationAmount
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
        VendorCategoryRule(keyword: "restaurant", category: "Restaurants & Cafes"),
        VendorCategoryRule(keyword: "cafe", category: "Restaurants & Cafes"),
        VendorCategoryRule(keyword: "coffee", category: "Restaurants & Cafes"),
        VendorCategoryRule(keyword: "bakery", category: "Restaurants & Cafes"),
        VendorCategoryRule(keyword: "cafeteria", category: "Restaurants & Cafes"),
        VendorCategoryRule(keyword: "grocery", category: "Grocery"),
        VendorCategoryRule(keyword: "supermarket", category: "Grocery"),
        VendorCategoryRule(keyword: "hypermarket", category: "Grocery"),
        VendorCategoryRule(keyword: "mini mart", category: "Grocery"),
        VendorCategoryRule(keyword: "mini market", category: "Grocery"),
        VendorCategoryRule(keyword: "petrol", category: "Fuel"),
        VendorCategoryRule(keyword: "fuel", category: "Fuel"),
        VendorCategoryRule(keyword: "taxi", category: "Transport"),
        VendorCategoryRule(keyword: "pharmacy", category: "Health"),
        VendorCategoryRule(keyword: "clinic", category: "Health"),
        VendorCategoryRule(keyword: "hospital", category: "Health"),
        VendorCategoryRule(keyword: "medical", category: "Health")
    ]
}

struct ExpenseBudget: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var categories: [String]
    var monthlyAmount: Decimal
    var currencyCode: String
    var alertsEnabled: Bool
    var cycleStartDay: Int
    var cycleEndDay: Int

    init(
        id: UUID = UUID(),
        name: String = "",
        categories: [String],
        monthlyAmount: Decimal,
        currencyCode: String,
        alertsEnabled: Bool = true,
        cycleStartDay: Int = 1,
        cycleEndDay: Int = 28
    ) {
        self.id = id
        self.name = name
        self.categories = categories
        self.monthlyAmount = monthlyAmount
        self.currencyCode = currencyCode
        self.alertsEnabled = alertsEnabled
        self.cycleStartDay = min(max(cycleStartDay, 1), 28)
        self.cycleEndDay = min(max(cycleEndDay, 1), 28)
    }

    var displayName: String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty { return cleaned }
        if categories.count == 1 { return categories[0] }
        return "Monthly Budget"
    }

    func includes(category: String) -> Bool {
        categories.contains { $0.caseInsensitiveCompare(category) == .orderedSame }
    }

    func dateInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        let day = min(max(cycleStartDay, 1), 28)
        var components = calendar.dateComponents([.year, .month], from: date)
        components.day = day
        guard var start = calendar.date(from: components) else { return nil }
        if date < start {
            guard let previous = calendar.date(byAdding: .month, value: -1, to: start) else {
                return nil
            }
            start = previous
        }

        let endMonthOffset = cycleEndDay >= cycleStartDay ? 0 : 1
        guard let endMonth = calendar.date(byAdding: .month, value: endMonthOffset, to: start) else {
            return nil
        }
        var endComponents = calendar.dateComponents([.year, .month], from: endMonth)
        endComponents.day = min(max(cycleEndDay, 1), 28)
        guard let inclusiveEnd = calendar.date(from: endComponents),
              let end = calendar.date(byAdding: .day, value: 1, to: inclusiveEnd) else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, categories, category, monthlyAmount, currencyCode, alertsEnabled
        case cycleStartDay, cycleEndDay
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let legacyCategory = try values.decodeIfPresent(String.self, forKey: .category)
        categories = try values.decodeIfPresent([String].self, forKey: .categories)
            ?? legacyCategory.map { [$0] }
            ?? []
        name = try values.decodeIfPresent(String.self, forKey: .name)
            ?? legacyCategory
            ?? ""
        monthlyAmount = try values.decodeIfPresent(Decimal.self, forKey: .monthlyAmount) ?? 0
        currencyCode = try values.decodeIfPresent(String.self, forKey: .currencyCode) ?? "QAR"
        alertsEnabled = try values.decodeIfPresent(Bool.self, forKey: .alertsEnabled) ?? true
        cycleStartDay = min(
            max(try values.decodeIfPresent(Int.self, forKey: .cycleStartDay) ?? 1, 1),
            28
        )
        cycleEndDay = min(
            max(try values.decodeIfPresent(Int.self, forKey: .cycleEndDay) ?? 28, 1),
            28
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(categories, forKey: .categories)
        try values.encode(monthlyAmount, forKey: .monthlyAmount)
        try values.encode(currencyCode, forKey: .currencyCode)
        try values.encode(alertsEnabled, forKey: .alertsEnabled)
        try values.encode(cycleStartDay, forKey: .cycleStartDay)
        try values.encode(cycleEndDay, forKey: .cycleEndDay)
    }
}

struct LedgerSettings: Codable, Equatable {
    var currencyCode: String
    var vendorRules: [VendorCategoryRule]
    var defaultAccountID: UUID?
    var expenseBudgets: [ExpenseBudget]
    var customExpenseCategories: [String]
    var customIncomeCategories: [String]
    var hiddenExpenseCategories: [String]
    var hiddenIncomeCategories: [String]
    var expenseCategoryCodes: [String: String]
    var incomeCategoryCodes: [String: String]
    var chartOfAccountsMigrationVersion: Int

    init(
        currencyCode: String = "QAR",
        vendorRules: [VendorCategoryRule] = VendorCategoryRule.defaults,
        defaultAccountID: UUID? = nil,
        expenseBudgets: [ExpenseBudget] = [],
        customExpenseCategories: [String] = [],
        customIncomeCategories: [String] = [],
        hiddenExpenseCategories: [String] = [],
        hiddenIncomeCategories: [String] = [],
        expenseCategoryCodes: [String: String] = LedgerTransaction.defaultExpenseCategoryCodes,
        incomeCategoryCodes: [String: String] = LedgerTransaction.defaultIncomeCategoryCodes,
        chartOfAccountsMigrationVersion: Int = 1
    ) {
        self.currencyCode = currencyCode
        self.vendorRules = vendorRules
        self.defaultAccountID = defaultAccountID
        self.expenseBudgets = expenseBudgets
        self.customExpenseCategories = customExpenseCategories
        self.customIncomeCategories = customIncomeCategories
        self.hiddenExpenseCategories = hiddenExpenseCategories
        self.hiddenIncomeCategories = hiddenIncomeCategories
        self.expenseCategoryCodes = expenseCategoryCodes
        self.incomeCategoryCodes = incomeCategoryCodes
        self.chartOfAccountsMigrationVersion = chartOfAccountsMigrationVersion
    }

    private enum CodingKeys: String, CodingKey {
        case currencyCode
        case vendorRules
        case defaultAccountID
        case expenseBudgets
        case customExpenseCategories
        case customIncomeCategories
        case hiddenExpenseCategories
        case hiddenIncomeCategories
        case expenseCategoryCodes
        case incomeCategoryCodes
        case chartOfAccountsMigrationVersion
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        currencyCode = try values.decodeIfPresent(String.self, forKey: .currencyCode) ?? "QAR"
        vendorRules = try values.decodeIfPresent([VendorCategoryRule].self, forKey: .vendorRules)
            ?? VendorCategoryRule.defaults
        defaultAccountID = try values.decodeIfPresent(UUID.self, forKey: .defaultAccountID)
        expenseBudgets = try values.decodeIfPresent([ExpenseBudget].self, forKey: .expenseBudgets) ?? []
        customExpenseCategories = try values.decodeIfPresent([String].self, forKey: .customExpenseCategories) ?? []
        customIncomeCategories = try values.decodeIfPresent([String].self, forKey: .customIncomeCategories) ?? []
        hiddenExpenseCategories = try values.decodeIfPresent([String].self, forKey: .hiddenExpenseCategories) ?? []
        hiddenIncomeCategories = try values.decodeIfPresent([String].self, forKey: .hiddenIncomeCategories) ?? []
        expenseCategoryCodes = try values.decodeIfPresent(
            [String: String].self,
            forKey: .expenseCategoryCodes
        ) ?? LedgerTransaction.defaultExpenseCategoryCodes
        incomeCategoryCodes = try values.decodeIfPresent(
            [String: String].self,
            forKey: .incomeCategoryCodes
        ) ?? LedgerTransaction.defaultIncomeCategoryCodes
        chartOfAccountsMigrationVersion = try values.decodeIfPresent(
            Int.self,
            forKey: .chartOfAccountsMigrationVersion
        ) ?? 1
    }
}

struct LedgerData: Codable {
    var version: Int
    var transactions: [LedgerTransaction]
    var accounts: [LedgerAccount]
    var settings: LedgerSettings

    init(
        version: Int = 5,
        transactions: [LedgerTransaction] = [],
        accounts: [LedgerAccount] = [LedgerAccount.legacyMain],
        settings: LedgerSettings = LedgerSettings()
    ) {
        self.version = version
        self.transactions = transactions
        self.accounts = accounts
        self.settings = settings
        normalize()
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case transactions
        case accounts
        case settings
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        transactions = try values.decodeIfPresent([LedgerTransaction].self, forKey: .transactions) ?? []
        accounts = try values.decodeIfPresent([LedgerAccount].self, forKey: .accounts) ?? []
        settings = try values.decodeIfPresent(LedgerSettings.self, forKey: .settings) ?? LedgerSettings()
        normalize()
    }

    mutating func normalize() {
        if accounts.isEmpty {
            accounts = [LedgerAccount.legacyMain]
        }
        let activeAccounts = accounts.filter { !$0.isArchived }
        let fallbackID = settings.defaultAccountID.flatMap { id in
            activeAccounts.contains(where: { $0.id == id }) ? id : nil
        } ?? activeAccounts.first?.id ?? accounts[0].id
        settings.defaultAccountID = fallbackID
        for index in transactions.indices where transactions[index].accountID == nil {
            transactions[index].accountID = fallbackID
        }
        settings.chartOfAccountsMigrationVersion = max(settings.chartOfAccountsMigrationVersion, 1)
        version = 5
    }
}

extension LedgerTransaction {
    static let expenseCategories = [
        "Restaurants & Cafes", "Grocery", "Shopping", "Transport", "Bills", "Fuel",
        "Health", "Home", "Family", "Entertainment", "Other"
    ]

    static let incomeCategories = [
        "Salary", "Business", "Refund", "Gift", "Investment", "Other"
    ]

    static let defaultIncomeCategoryCodes = [
        "Salary": "4010", "Business": "4020", "Refund": "4030",
        "Gift": "4040", "Investment": "4050", "Other": "4090"
    ]

    static let defaultExpenseCategoryCodes = [
        "Restaurants & Cafes": "5010", "Grocery": "5020", "Shopping": "5030",
        "Transport": "5040", "Bills": "5050", "Fuel": "5060", "Health": "5070",
        "Home": "5080", "Family": "5090", "Entertainment": "5100", "Other": "5990"
    ]
}
