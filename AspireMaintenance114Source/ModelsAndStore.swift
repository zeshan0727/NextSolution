import Foundation
import UserNotifications

// MARK: - Core Models

struct CompanyProfile: Codable, Equatable {
    var fullName: String
    var tradingName: String
    var address: String
    var phone: String
    var email: String
    var website: String
    var taxRegistrationNumber: String
    var bankName: String
    var accountHolderName: String
    var accountNumber: String
    var iban: String
    var swiftCode: String
    var currencyCode: String
    var invoicePrefix: String
    var paymentTermsDays: Int
    var invoiceTerms: String
    var longOverdueDays: Int

    static let aspireDefault = CompanyProfile(
        fullName: "Aspire Green Garden Designing and Works LLC",
        tradingName: "Aspire Garden",
        address: "United Arab Emirates",
        phone: "+971 58 608 0000",
        email: "sales@aspiregroupae.com",
        website: "aspiregroupae.com",
        taxRegistrationNumber: "",
        bankName: "",
        accountHolderName: "",
        accountNumber: "",
        iban: "",
        swiftCode: "",
        currencyCode: "AED",
        invoicePrefix: "ASP",
        paymentTermsDays: 7,
        invoiceTerms: "Kindly transfer the invoice amount to the company bank account. Thank you.",
        longOverdueDays: 30
    )
}

struct Customer: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var address: String
    var villaNumber: String? = nil
    var area: String? = nil
    var email: String
    var phone: String
    var monthlyRate: Double
    var plannedVisitsPerMonth: Int
    var notes: String
    var isActive: Bool
    var createdAt: Date = Date()
}

struct MaintenanceVisit: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var customerID: UUID
    var date: Date
    var staffName: String
    var workDone: String
    var notes: String
}

struct InvoiceLineItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var description: String
    var quantity: Double
    var unitPrice: Double

    var amount: Double { quantity * unitPrice }
}

enum InvoiceStatus: String, CaseIterable, Codable, Identifiable {
    case draft
    case sent
    case partial
    case paid
    case void

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft: return "Draft"
        case .sent: return "Sent"
        case .partial: return "Part Paid"
        case .paid: return "Paid"
        case .void: return "Void"
        }
    }
}

struct Invoice: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var number: String
    var customerID: UUID
    var issueDate: Date
    var dueDate: Date
    var serviceMonth: Date
    var lineItems: [InvoiceLineItem]
    var status: InvoiceStatus
    var amountPaid: Double
    var notes: String
    var sentAt: Date?
    var paidAt: Date?
    var createdAt: Date = Date()

    var total: Double { lineItems.reduce(0) { $0 + $1.amount } }
    var outstanding: Double { max(0, total - amountPaid) }

    func isOverdue(asOf date: Date = Date()) -> Bool {
        status != .paid && status != .void && outstanding > 0 && dueDate < Calendar.current.startOfDay(for: date)
    }

    func overdueDays(asOf date: Date = Date()) -> Int {
        guard isOverdue(asOf: date) else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: dueDate, to: date).day ?? 0)
    }
}

enum ExpenseCategory: String, CaseIterable, Codable, Identifiable {
    case fuel = "Fuel"
    case salaries = "Salaries & Labour"
    case plants = "Plants & Materials"
    case equipment = "Tools & Equipment"
    case vehicle = "Vehicle & Transport"
    case subcontractor = "Subcontractor"
    case utilities = "Utilities"
    case office = "Office & Administration"
    case other = "Other"

    var id: String { rawValue }
}

struct Expense: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var category: ExpenseCategory
    var vendor: String
    var amount: Double
    var paymentAccount: String
    var notes: String
}

enum EmailDeliveryMode: String, CaseIterable, Codable, Identifiable {
    case gmailDirect
    case appleMail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gmailDirect: return "Gmail Direct"
        case .appleMail: return "Apple Mail Assisted"
        }
    }
}

struct EmailConfiguration: Codable, Equatable {
    var schedulerEndpoint: String
    var connectorID: String
    var connectedEmail: String
    var signature: String
    var preferredMode: EmailDeliveryMode

    static let aspireDefault = EmailConfiguration(
        schedulerEndpoint: "",
        connectorID: "",
        connectedEmail: "",
        signature: "Thank you,\nAspire Green Garden Designing and Works LLC",
        preferredMode: .gmailDirect
    )
}

struct AspireData: Codable {
    var company: CompanyProfile
    var customers: [Customer]
    var visits: [MaintenanceVisit]
    var invoices: [Invoice]
    var expenses: [Expense]
    var emailConfiguration: EmailConfiguration

    static let empty = AspireData(
        company: .aspireDefault,
        customers: [],
        visits: [],
        invoices: [],
        expenses: [],
        emailConfiguration: .aspireDefault
    )
}

struct AgingSummary {
    var current: Double = 0
    var days1To30: Double = 0
    var days31To60: Double = 0
    var days61To90: Double = 0
    var over90: Double = 0

    var total: Double { current + days1To30 + days31To60 + days61To90 + over90 }
}

// MARK: - Store

@MainActor
final class AspireStore: ObservableObject {
    @Published private(set) var data: AspireData
    @Published var lastErrorMessage: String?

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let dataURL: URL

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("AspireMaintenance", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        dataURL = directory.appendingPathComponent("aspire-maintenance-data.json")

        if let stored = try? Data(contentsOf: dataURL),
           let decoded = try? decoder.decode(AspireData.self, from: stored) {
            data = decoded
        } else {
            data = .empty
        }
    }

    var company: CompanyProfile { data.company }
    var customers: [Customer] { data.customers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
    var activeCustomers: [Customer] { customers.filter(\.isActive) }
    var invoices: [Invoice] { data.invoices.sorted { $0.issueDate > $1.issueDate } }
    var expenses: [Expense] { data.expenses.sorted { $0.date > $1.date } }
    var visits: [MaintenanceVisit] { data.visits.sorted { $0.date > $1.date } }
    var emailConfiguration: EmailConfiguration { data.emailConfiguration }

    func customer(id: UUID) -> Customer? {
        data.customers.first { $0.id == id }
    }

    func visits(for customerID: UUID, in month: Date? = nil) -> [MaintenanceVisit] {
        data.visits.filter { visit in
            guard visit.customerID == customerID else { return false }
            guard let month else { return true }
            return Calendar.current.isDate(visit.date, equalTo: month, toGranularity: .month)
        }.sorted { $0.date > $1.date }
    }

    func invoices(for customerID: UUID) -> [Invoice] {
        invoices.filter { $0.customerID == customerID }
    }

    func invoice(id: UUID) -> Invoice? {
        data.invoices.first { $0.id == id }
    }

    func expense(id: UUID) -> Expense? {
        data.expenses.first { $0.id == id }
    }

    func updateCompany(_ company: CompanyProfile) {
        data.company = company
        persist()
    }

    func updateEmailConfiguration(_ configuration: EmailConfiguration) {
        data.emailConfiguration = configuration
        persist()
    }

    func addCustomer(_ customer: Customer) {
        data.customers.append(customer)
        persist()
    }

    func updateCustomer(_ customer: Customer) {
        guard let index = data.customers.firstIndex(where: { $0.id == customer.id }) else { return }
        data.customers[index] = customer
        persist()
    }

    func deleteCustomers(at offsets: IndexSet, from displayedCustomers: [Customer]) {
        let ids = offsets.map { displayedCustomers[$0].id }
        data.customers.removeAll { ids.contains($0.id) }
        data.visits.removeAll { ids.contains($0.customerID) }
        data.invoices.removeAll { ids.contains($0.customerID) }
        persist()
    }

    func addVisit(_ visit: MaintenanceVisit) {
        data.visits.append(visit)
        persist()
    }

    @discardableResult
    func createMonthlyInvoice(for customer: Customer, serviceMonth: Date, customAmount: Double? = nil) -> Invoice {
        let calendar = Calendar.current
        let normalizedMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: serviceMonth)) ?? serviceMonth
        let issueDate = Date()
        let dueDate = calendar.date(byAdding: .day, value: max(0, company.paymentTermsDays), to: issueDate) ?? issueDate
        let monthName = DateFormatter.monthAndYear.string(from: normalizedMonth)
        let amount = customAmount ?? customer.monthlyRate
        let invoice = Invoice(
            number: nextInvoiceNumber(for: issueDate),
            customerID: customer.id,
            issueDate: issueDate,
            dueDate: dueDate,
            serviceMonth: normalizedMonth,
            lineItems: [InvoiceLineItem(description: "Garden Maintenance Charges (Monthly) – \(monthName)", quantity: 1, unitPrice: amount)],
            status: .draft,
            amountPaid: 0,
            notes: company.invoiceTerms,
            sentAt: nil,
            paidAt: nil
        )
        data.invoices.append(invoice)
        persist()
        return invoice
    }

    func addInvoice(_ invoice: Invoice) {
        data.invoices.append(invoice)
        persist()
    }

    func updateInvoice(_ invoice: Invoice) {
        guard let index = data.invoices.firstIndex(where: { $0.id == invoice.id }) else { return }
        data.invoices[index] = invoice
        persist()
    }

    func markInvoiceSent(_ id: UUID) {
        guard let index = data.invoices.firstIndex(where: { $0.id == id }) else { return }
        data.invoices[index].status = data.invoices[index].amountPaid > 0 ? .partial : .sent
        data.invoices[index].sentAt = Date()
        persist()
    }

    func recordPayment(invoiceID: UUID, amount: Double, paymentDate: Date) {
        guard let index = data.invoices.firstIndex(where: { $0.id == invoiceID }) else { return }
        let newPaid = min(data.invoices[index].total, max(0, data.invoices[index].amountPaid + amount))
        data.invoices[index].amountPaid = newPaid
        if newPaid >= data.invoices[index].total - 0.005 {
            data.invoices[index].status = .paid
            data.invoices[index].paidAt = paymentDate
        } else if newPaid > 0 {
            data.invoices[index].status = .partial
        }
        persist()
    }

    func deleteInvoice(_ id: UUID) {
        data.invoices.removeAll { $0.id == id }
        persist()
    }

    func addExpense(_ expense: Expense) {
        data.expenses.append(expense)
        persist()
    }

    func updateExpense(_ expense: Expense) {
        guard let index = data.expenses.firstIndex(where: { $0.id == expense.id }) else { return }
        data.expenses[index] = expense
        persist()
    }

    func deleteExpenses(at offsets: IndexSet, from displayedExpenses: [Expense]) {
        let ids = offsets.map { displayedExpenses[$0].id }
        data.expenses.removeAll { ids.contains($0.id) }
        persist()
    }

    func generateMonthlyInvoices(for month: Date) -> [Invoice] {
        var generated: [Invoice] = []
        for customer in activeCustomers {
            let exists = data.invoices.contains {
                $0.customerID == customer.id &&
                Calendar.current.isDate($0.serviceMonth, equalTo: month, toGranularity: .month) &&
                $0.status != .void
            }
            if !exists {
                generated.append(createMonthlyInvoice(for: customer, serviceMonth: month))
            }
        }
        return generated
    }

    func invoicedIncome(in month: Date) -> Double {
        data.invoices.filter {
            $0.status != .void && Calendar.current.isDate($0.issueDate, equalTo: month, toGranularity: .month)
        }.reduce(0) { $0 + $1.total }
    }

    func collectedIncome(in month: Date) -> Double {
        data.invoices.filter {
            guard let paidAt = $0.paidAt else { return false }
            return Calendar.current.isDate(paidAt, equalTo: month, toGranularity: .month)
        }.reduce(0) { $0 + $1.amountPaid }
    }

    func expensesTotal(in month: Date) -> Double {
        data.expenses.filter {
            Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month)
        }.reduce(0) { $0 + $1.amount }
    }

    func outstandingTotal() -> Double {
        data.invoices.filter { $0.status != .void }.reduce(0) { $0 + $1.outstanding }
    }

    func overdueInvoices(asOf date: Date = Date()) -> [Invoice] {
        invoices.filter { $0.isOverdue(asOf: date) }
    }

    func longOverdueInvoices(asOf date: Date = Date()) -> [Invoice] {
        overdueInvoices(asOf: date).filter { $0.overdueDays(asOf: date) >= company.longOverdueDays }
    }

    func agingSummary(asOf date: Date = Date()) -> AgingSummary {
        var summary = AgingSummary()
        for invoice in data.invoices where invoice.status != .void && invoice.outstanding > 0 {
            let days = invoice.overdueDays(asOf: date)
            if !invoice.isOverdue(asOf: date) {
                summary.current += invoice.outstanding
            } else if days <= 30 {
                summary.days1To30 += invoice.outstanding
            } else if days <= 60 {
                summary.days31To60 += invoice.outstanding
            } else if days <= 90 {
                summary.days61To90 += invoice.outstanding
            } else {
                summary.over90 += invoice.outstanding
            }
        }
        return summary
    }

    func exportData() throws -> Data {
        try encoder.encode(data)
    }

    func importData(_ importedData: Data) throws {
        data = try decoder.decode(AspireData.self, from: importedData)
        persist()
    }

    func addDemoData() {
        guard data.customers.isEmpty && data.invoices.isEmpty && data.expenses.isEmpty else { return }
        let customer = Customer(
            name: "Sample Garden Customer",
            address: "Abu Dhabi, UAE",
            email: "customer@example.com",
            phone: "+971 50 000 0000",
            monthlyRate: 600,
            plannedVisitsPerMonth: 3,
            notes: "Demo record for first testing. Delete it when finished.",
            isActive: true
        )
        data.customers.append(customer)
        let invoice = createMonthlyInvoice(for: customer, serviceMonth: Date())
        data.invoices = data.invoices.map { current in
            var updated = current
            if current.id == invoice.id {
                updated.issueDate = Calendar.current.date(byAdding: .day, value: -45, to: Date()) ?? Date()
                updated.dueDate = Calendar.current.date(byAdding: .day, value: -38, to: Date()) ?? Date()
                updated.status = .sent
            }
            return updated
        }
        data.expenses.append(Expense(date: Date(), category: .fuel, vendor: "Sample Fuel", amount: 120, paymentAccount: "Cash", notes: "Demo expense"))
        persist()
    }

    func requestNotificationsAndRefresh() async {
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if granted { await refreshOverdueNotifications() }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func refreshOverdueNotifications() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["aspire.long-overdue"])
        let overdue = longOverdueInvoices()
        guard !overdue.isEmpty else { return }

        let total = overdue.reduce(0) { $0 + $1.outstanding }
        let content = UNMutableNotificationContent()
        content.title = "Long-overdue invoices"
        content.body = "\(overdue.count) invoice(s) are overdue by at least \(company.longOverdueDays) days. Outstanding: \(currency(total))."
        content.sound = .default
        content.badge = NSNumber(value: overdue.count)

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "aspire.long-overdue", content: content, trigger: trigger)
        try? await center.add(request)
    }

    func currency(_ amount: Double) -> String {
        CurrencyFormatter.string(amount, code: company.currencyCode)
    }

    private func nextInvoiceNumber(for date: Date) -> String {
        let month = DateFormatter.invoiceMonth.string(from: date)
        let prefix = company.invoicePrefix.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().isEmpty
            ? "ASP"
            : company.invoicePrefix.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let sameMonthCount = data.invoices.filter {
            DateFormatter.invoiceMonth.string(from: $0.issueDate) == month
        }.count + 1
        return String(format: "%@-%@-%03d", prefix, month, sameMonthCount)
    }

    private func persist() {
        do {
            let encoded = try encoder.encode(data)
            try encoded.write(to: dataURL, options: .atomic)
            objectWillChange.send()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}

// MARK: - Formatting

enum CurrencyFormatter {
    static func string(_ amount: Double, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code.isEmpty ? "AED" : code
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%@ %.2f", code, amount)
    }
}

extension DateFormatter {
    static let monthAndYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    static let invoiceMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMM"
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}

extension Calendar {
    func addingMonths(_ value: Int, to date: Date) -> Date {
        self.date(byAdding: .month, value: value, to: date) ?? date
    }
}
