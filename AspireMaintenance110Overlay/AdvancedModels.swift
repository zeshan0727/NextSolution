import Foundation

struct Employee: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var role: String
    var phone: String
    var email: String
    var monthlySalary: Double
    var joiningDate: Date
    var isActive: Bool
    var notes: String
}

struct BankAccount: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var label: String
    var bankName: String
    var accountHolderName: String
    var accountNumber: String
    var iban: String
    var swiftCode: String
    var currencyCode: String
    var isDefault: Bool
}

struct AdvancePayment: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var customerID: UUID
    var date: Date
    var amount: Double
    var paymentAccount: String
    var reference: String
    var notes: String
    var employeeID: UUID?
}

struct ExpenseRefund: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var expenseID: UUID
    var date: Date
    var amount: Double
    var notes: String
}

struct InvoicePDFOverlayImage: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var imageData: Data
    /// Normalized A4 coordinates (0...1), so the layout stays device-independent.
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct InvoicePDFSettings: Codable, Equatable, Hashable {
    var showLogo: Bool
    var showCompanyName: Bool
    var showCompanyContact: Bool
    var showBillTo: Bool
    var showInvoiceMeta: Bool
    var showItems: Bool
    var showPayment: Bool
    var showTerms: Bool
    var showFooter: Bool
    var showPaymentStatus: Bool

    var invoiceTitle: String
    var billToTitle: String
    var paymentTitle: String
    var termsTitle: String
    var footerText: String
    var paidText: String
    var unpaidText: String
    var partialPaidText: String
    var companyNameOverride: String
    var companyContactOverride: String
    var logoData: Data?
    var overlayImages: [InvoicePDFOverlayImage]

    static let aspireDefault = InvoicePDFSettings(
        showLogo: true,
        showCompanyName: true,
        showCompanyContact: true,
        showBillTo: true,
        showInvoiceMeta: true,
        showItems: true,
        showPayment: true,
        showTerms: true,
        showFooter: true,
        showPaymentStatus: true,
        invoiceTitle: "INVOICE",
        billToTitle: "BILL TO",
        paymentTitle: "PAYMENT METHOD",
        termsTitle: "TERMS OR NOTES",
        footerText: "Built on Service  •  Landscaping  •  Gardening  •  General Maintenance",
        paidText: "PAID",
        unpaidText: "UNPAID",
        partialPaidText: "PART PAID",
        companyNameOverride: "",
        companyContactOverride: "",
        logoData: nil,
        overlayImages: []
    )
}

enum PDFEditableZone: String, CaseIterable, Identifiable {
    case logo
    case companyName
    case companyContact
    case invoiceTitle
    case paymentStatus
    case billTo
    case invoiceMeta
    case items
    case payment
    case terms
    case footer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .logo: return "Logo"
        case .companyName: return "Company Name"
        case .companyContact: return "Company Contact"
        case .invoiceTitle: return "Invoice Title"
        case .paymentStatus: return "Paid / Unpaid Status"
        case .billTo: return "Bill To"
        case .invoiceMeta: return "Invoice Dates"
        case .items: return "Invoice Items"
        case .payment: return "Payment Details"
        case .terms: return "Terms / Notes"
        case .footer: return "Footer"
        }
    }
}

enum ReceivableDashboardKind: String, CaseIterable, Identifiable {
    case outstanding
    case overdue
    case longOverdue
    case advances

    var id: String { rawValue }
    var title: String {
        switch self {
        case .outstanding: return "Outstanding Receivables"
        case .overdue: return "Overdue Receivables"
        case .longOverdue: return "30+ Days Receivables"
        case .advances: return "Advance Collections"
        }
    }
}
