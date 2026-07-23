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

extension LedgerTransaction {
    static func vendorFromMessage(_ text: String) -> String? {
        let patterns = [
            #"(?i)\b(?:at|to|merchant)\s+([A-Z0-9][A-Z0-9 '&.-]{1,40}?)(?=\s+(?:on|at|for|using|card|amount|date|available)\b|[,.;\n]|$)"#,
            #"(?i)\bfrom\s+([A-Z0-9][A-Z0-9 '&.-]{1,40}?)(?=\s+(?:on|at|for|using|card|amount|date)\b|[,.;\n]|$)"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            let value = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2 { return value }
        }
        return nil
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

    static let defaults: [VendorCategoryRule] = []
}

struct LedgerSettings: Codable, Equatable {
    var currencyCode: String
    var vendorRules: [VendorCategoryRule]
    var smsAutoImportEnabled: Bool
    var defaultAccountID: UUID?
    var smsMatchText: String
    var smsDestinationAccountID: UUID?
    var smsRescanRequestID: Int
    var smsImporterLastCheck: Date?
    var smsImporterLastResult: String?

    init(
        currencyCode: String = "QAR",
        vendorRules: [VendorCategoryRule] = [],
        smsAutoImportEnabled: Bool = true,
        defaultAccountID: UUID? = nil,
        smsMatchText: String = "**6760",
        smsDestinationAccountID: UUID? = nil,
        smsRescanRequestID: Int = 0,
        smsImporterLastCheck: Date? = nil,
        smsImporterLastResult: String? = nil
    ) {
        self.currencyCode = currencyCode
        self.vendorRules = vendorRules
        self.smsAutoImportEnabled = smsAutoImportEnabled
        self.defaultAccountID = defaultAccountID
        self.smsMatchText = smsMatchText
        self.smsDestinationAccountID = smsDestinationAccountID
        self.smsRescanRequestID = smsRescanRequestID
        self.smsImporterLastCheck = smsImporterLastCheck
        self.smsImporterLastResult = smsImporterLastResult
    }

    private enum CodingKeys: String, CodingKey {
        case currencyCode
        case vendorRules
        case smsAutoImportEnabled
        case defaultAccountID
        case smsMatchText
        case smsDestinationAccountID
        case smsRescanRequestID
        case smsImporterLastCheck
        case smsImporterLastResult
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        currencyCode = try values.decodeIfPresent(String.self, forKey: .currencyCode) ?? "QAR"
        vendorRules = try values.decodeIfPresent([VendorCategoryRule].self, forKey: .vendorRules)
            ?? []
        smsAutoImportEnabled = try values.decodeIfPresent(Bool.self, forKey: .smsAutoImportEnabled) ?? true
        defaultAccountID = try values.decodeIfPresent(UUID.self, forKey: .defaultAccountID)
        smsMatchText = try values.decodeIfPresent(String.self, forKey: .smsMatchText) ?? "**6760"
        smsDestinationAccountID = try values.decodeIfPresent(UUID.self, forKey: .smsDestinationAccountID)
        smsRescanRequestID = try values.decodeIfPresent(Int.self, forKey: .smsRescanRequestID) ?? 0
        smsImporterLastCheck = try values.decodeIfPresent(Date.self, forKey: .smsImporterLastCheck)
        smsImporterLastResult = try values.decodeIfPresent(String.self, forKey: .smsImporterLastResult)
    }
}

struct LedgerData: Codable {
    var version: Int
    var transactions: [LedgerTransaction]
    var accounts: [LedgerAccount]
    var settings: LedgerSettings

    init(
        version: Int = 3,
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
        if settings.smsDestinationAccountID == nil ||
            !activeAccounts.contains(where: { $0.id == settings.smsDestinationAccountID }) {
            settings.smsDestinationAccountID = activeAccounts.first(where: {
                $0.name.caseInsensitiveCompare("Credit Card") == .orderedSame
            })?.id ?? fallbackID
        }
        for index in transactions.indices where transactions[index].accountID == nil {
            transactions[index].accountID = fallbackID
        }
        for index in transactions.indices where transactions[index].vendor?.isEmpty != false {
            transactions[index].vendor = LedgerTransaction.vendorFromMessage(transactions[index].details)
        }
        version = 3
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
}
