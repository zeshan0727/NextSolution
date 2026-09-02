import MessageUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - App Shell

struct AppRootView: View {
    @EnvironmentObject private var store: AspireStore
    @State private var showingError = false

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }

            CustomersView()
                .tabItem { Label("Customers", systemImage: "person.2.fill") }

            InvoicesView()
                .tabItem { Label("Invoices", systemImage: "doc.text.fill") }

            FinanceView()
                .tabItem { Label("Finance", systemImage: "chart.line.uptrend.xyaxis") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.aspireGreen)
        .onChange(of: store.lastErrorMessage) { value in
            showingError = value != nil
        }
        .alert("Aspire Maintenance", isPresented: $showingError) {
            Button("OK") { store.lastErrorMessage = nil }
        } message: {
            Text(store.lastErrorMessage ?? "Unknown error")
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @EnvironmentObject private var store: AspireStore
    @State private var selectedMonth = Date()

    private var invoiced: Double { store.invoicedIncome(in: selectedMonth) }
    private var collected: Double { store.collectedIncome(in: selectedMonth) }
    private var expenses: Double { store.expensesTotal(in: selectedMonth) }
    private var profit: Double { invoiced - expenses }
    private var overdue: [Invoice] { store.overdueInvoices() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AspireHeaderCard()
                    MonthPicker(month: $selectedMonth)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        SummaryCard(title: "Invoiced", value: store.currency(invoiced), subtitle: DateFormatter.monthAndYear.string(from: selectedMonth), icon: "doc.text.fill")
                        SummaryCard(title: "Collected", value: store.currency(collected), subtitle: "Payments received", icon: "checkmark.circle.fill")
                        SummaryCard(title: "Expenses", value: store.currency(expenses), subtitle: "Recorded costs", icon: "fuelpump.fill")
                        SummaryCard(title: "Profit / Loss", value: store.currency(profit), subtitle: profit >= 0 ? "Profit" : "Loss", icon: "chart.line.uptrend.xyaxis", emphasized: true)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Receivables", subtitle: "Outstanding and overdue customer bills")
                        HStack(spacing: 12) {
                            MetricPill(title: "Outstanding", value: store.currency(store.outstandingTotal()))
                            MetricPill(title: "Overdue", value: "\(overdue.count)")
                            MetricPill(title: "30+ Days", value: "\(store.longOverdueInvoices().count)")
                        }
                    }
                    .aspirePanel()

                    VisitProgressSection(month: selectedMonth)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Attention Needed", subtitle: "Oldest overdue invoices")
                        if overdue.isEmpty {
                            EmptyInlineView(icon: "checkmark.seal.fill", text: "No overdue invoices")
                        } else {
                            ForEach(overdue.sorted { $0.dueDate < $1.dueDate }.prefix(5)) { invoice in
                                NavigationLink {
                                    InvoiceDetailView(invoiceID: invoice.id)
                                } label: {
                                    InvoiceRow(invoice: invoice)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .aspirePanel()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Aspire Maintenance")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await store.refreshOverdueNotifications() }
                    } label: {
                        Image(systemName: "bell.badge")
                    }
                }
            }
        }
    }
}

struct VisitProgressSection: View {
    @EnvironmentObject private var store: AspireStore
    var month: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Monthly Visits", subtitle: "Planned garden maintenance progress")
            if store.activeCustomers.isEmpty {
                EmptyInlineView(icon: "leaf.fill", text: "Add active customers to track visits")
            } else {
                ForEach(store.activeCustomers.prefix(8)) { customer in
                    let completed = store.visits(for: customer.id, in: month).count
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(customer.name).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(completed) / \(customer.plannedVisitsPerMonth)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(completed >= customer.plannedVisitsPerMonth ? Color.aspireGreen : .secondary)
                        }
                        ProgressView(value: Double(min(completed, customer.plannedVisitsPerMonth)), total: Double(max(1, customer.plannedVisitsPerMonth)))
                            .tint(completed >= customer.plannedVisitsPerMonth ? .aspireGreen : .aspireGold)
                    }
                }
            }
        }
        .aspirePanel()
    }
}

// MARK: - Customers

struct CustomersView: View {
    @EnvironmentObject private var store: AspireStore
    @State private var searchText = ""
    @State private var showingEditor = false

    private var filteredCustomers: [Customer] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return store.customers }
        return store.customers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.email.localizedCaseInsensitiveContains(searchText) ||
            $0.phone.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredCustomers.isEmpty {
                    FullEmptyView(title: searchText.isEmpty ? "No Customers" : "No Results", icon: "person.2", message: searchText.isEmpty ? "Add permanent monthly maintenance customers." : "Try another customer name, phone or email.")
                } else {
                    List {
                        ForEach(filteredCustomers) { customer in
                            NavigationLink(value: customer.id) {
                                CustomerRow(customer: customer)
                            }
                        }
                        .onDelete { offsets in
                            store.deleteCustomers(at: offsets, from: filteredCustomers)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Customers")
            .searchable(text: $searchText, prompt: "Name, phone or email")
            .navigationDestination(for: UUID.self) { id in
                CustomerDetailView(customerID: id)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingEditor = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingEditor) {
                CustomerEditorView()
            }
        }
    }
}

struct CustomerRow: View {
    var customer: Customer

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.aspireGreen.opacity(0.12))
                Image(systemName: "leaf.fill").foregroundStyle(Color.aspireGreen)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(customer.name).font(.headline)
                Text(customer.email.isEmpty ? customer.phone : customer.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(customer.plannedVisitsPerMonth) visits/month")
                    .font(.caption2)
                    .foregroundStyle(customer.isActive ? Color.aspireGreen : .secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(CurrencyFormatter.string(customer.monthlyRate, code: "AED"))
                    .font(.subheadline.weight(.semibold))
                Text(customer.isActive ? "Active" : "Inactive")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((customer.isActive ? Color.aspireGreen : Color.gray).opacity(0.12), in: Capsule())
                    .foregroundStyle(customer.isActive ? Color.aspireGreen : .secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct CustomerDetailView: View {
    @EnvironmentObject private var store: AspireStore
    let customerID: UUID
    @State private var showingEditor = false
    @State private var showingVisit = false
    @State private var showingInvoice = false

    var body: some View {
        Group {
            if let customer = store.customer(id: customerID) {
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle().fill(Color.aspireGreen.opacity(0.12))
                                Image(systemName: "leaf.circle.fill")
                                    .font(.system(size: 46))
                                    .foregroundStyle(Color.aspireGreen)
                            }
                            .frame(width: 84, height: 84)
                            Text(customer.name).font(.title2.bold()).multilineTextAlignment(.center)
                            Text(customer.isActive ? "Active Monthly Customer" : "Inactive Customer")
                                .font(.subheadline)
                                .foregroundStyle(customer.isActive ? Color.aspireGreen : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .aspirePanel()

                        HStack(spacing: 12) {
                            MetricPill(title: "Monthly Bill", value: store.currency(customer.monthlyRate))
                            MetricPill(title: "Visits", value: "\(store.visits(for: customer.id, in: Date()).count)/\(customer.plannedVisitsPerMonth)")
                            MetricPill(title: "Invoices", value: "\(store.invoices(for: customer.id).count)")
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Contact & Site", subtitle: nil)
                            LabeledValue(icon: "mappin.and.ellipse", value: customer.address.isEmpty ? "No address" : customer.address)
                            LabeledValue(icon: "phone.fill", value: customer.phone.isEmpty ? "No phone" : customer.phone)
                            LabeledValue(icon: "envelope.fill", value: customer.email.isEmpty ? "No email" : customer.email)
                            if !customer.notes.isEmpty { LabeledValue(icon: "note.text", value: customer.notes) }
                        }
                        .aspirePanel()

                        HStack(spacing: 10) {
                            ActionButton(title: "Log Visit", icon: "checkmark.circle", style: .green) { showingVisit = true }
                            ActionButton(title: "Create Invoice", icon: "doc.badge.plus", style: .gold) { showingInvoice = true }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Recent Visits", subtitle: "Maintenance work history")
                            let visits = store.visits(for: customer.id)
                            if visits.isEmpty {
                                EmptyInlineView(icon: "calendar.badge.clock", text: "No visits recorded")
                            } else {
                                ForEach(visits.prefix(6)) { visit in
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(DateFormatter.shortDate.string(from: visit.date)).font(.subheadline.weight(.semibold))
                                            Spacer()
                                            Text(visit.staffName).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Text(visit.workDone).font(.subheadline)
                                        if !visit.notes.isEmpty { Text(visit.notes).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    if visit.id != visits.prefix(6).last?.id { Divider() }
                                }
                            }
                        }
                        .aspirePanel()

                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Invoices", subtitle: "Customer billing history")
                            let invoices = store.invoices(for: customer.id)
                            if invoices.isEmpty {
                                EmptyInlineView(icon: "doc.text", text: "No invoices created")
                            } else {
                                ForEach(invoices.prefix(8)) { invoice in
                                    NavigationLink {
                                        InvoiceDetailView(invoiceID: invoice.id)
                                    } label: {
                                        InvoiceRow(invoice: invoice)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .aspirePanel()
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Customer")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Edit") { showingEditor = true }
                    }
                }
                .sheet(isPresented: $showingEditor) { CustomerEditorView(existing: customer) }
                .sheet(isPresented: $showingVisit) { VisitEditorView(customer: customer) }
                .sheet(isPresented: $showingInvoice) { QuickInvoiceView(customer: customer) }
            } else {
                FullEmptyView(title: "Customer Not Found", icon: "person.crop.circle.badge.exclamationmark", message: "The customer record is no longer available.")
            }
        }
    }
}

struct CustomerEditorView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    var existing: Customer?

    @State private var name = ""
    @State private var address = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var monthlyRate = 0.0
    @State private var visitsPerMonth = 3
    @State private var notes = ""
    @State private var isActive = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    TextField("Customer name", text: $name)
                    TextField("Site address", text: $address, axis: .vertical).lineLimit(2...4)
                    TextField("Email", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress)
                    TextField("Phone", text: $phone).keyboardType(.phonePad)
                }
                Section("Monthly Maintenance") {
                    TextField("Monthly rate", value: $monthlyRate, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad)
                    Stepper("Planned visits: \(visitsPerMonth)", value: $visitsPerMonth, in: 1...12)
                    Toggle("Active monthly customer", isOn: $isActive)
                }
                Section("Notes") {
                    TextField("Access details, garden requirements or instructions", text: $notes, axis: .vertical).lineLimit(3...6)
                }
            }
            .navigationTitle(existing == nil ? "New Customer" : "Edit Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                guard let existing else { return }
                name = existing.name
                address = existing.address
                email = existing.email
                phone = existing.phone
                monthlyRate = existing.monthlyRate
                visitsPerMonth = existing.plannedVisitsPerMonth
                notes = existing.notes
                isActive = existing.isActive
            }
        }
    }

    private func save() {
        let customer = Customer(
            id: existing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            address: address.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
            monthlyRate: max(0, monthlyRate),
            plannedVisitsPerMonth: visitsPerMonth,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            isActive: isActive,
            createdAt: existing?.createdAt ?? Date()
        )
        if existing == nil { store.addCustomer(customer) } else { store.updateCustomer(customer) }
        dismiss()
    }
}

struct VisitEditorView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    let customer: Customer
    @State private var date = Date()
    @State private var staffName = ""
    @State private var workDone = "Garden maintenance visit"
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(customer.name) {
                    DatePicker("Visit date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    TextField("Team / staff name", text: $staffName)
                }
                Section("Work") {
                    TextField("Work completed", text: $workDone, axis: .vertical).lineLimit(2...5)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle("Log Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.addVisit(MaintenanceVisit(customerID: customer.id, date: date, staffName: staffName, workDone: workDone, notes: notes))
                        dismiss()
                    }
                    .disabled(workDone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Invoices

private enum InvoiceFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case draft = "Draft"
    case sent = "Sent"
    case overdue = "Overdue"
    case paid = "Paid"
    var id: String { rawValue }
}

struct InvoicesView: View {
    @EnvironmentObject private var store: AspireStore
    @State private var filter: InvoiceFilter = .all
    @State private var searchText = ""
    @State private var showingNewInvoice = false
    @State private var showingBulkGenerate = false

    private var displayedInvoices: [Invoice] {
        store.invoices.filter { invoice in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .draft: matchesFilter = invoice.status == .draft
            case .sent: matchesFilter = invoice.status == .sent || invoice.status == .partial
            case .overdue: matchesFilter = invoice.isOverdue()
            case .paid: matchesFilter = invoice.status == .paid
            }
            guard matchesFilter else { return false }
            guard !searchText.isEmpty else { return true }
            let customerName = store.customer(id: invoice.customerID)?.name ?? ""
            return invoice.number.localizedCaseInsensitiveContains(searchText) || customerName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $filter) {
                    ForEach(InvoiceFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                if displayedInvoices.isEmpty {
                    FullEmptyView(title: "No Invoices", icon: "doc.text", message: "Create a monthly customer invoice or generate all monthly invoices together.")
                } else {
                    List(displayedInvoices) { invoice in
                        NavigationLink(value: invoice.id) { InvoiceRow(invoice: invoice) }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Invoices")
            .searchable(text: $searchText, prompt: "Invoice number or customer")
            .navigationDestination(for: UUID.self) { id in InvoiceDetailView(invoiceID: id) }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { showingNewInvoice = true } label: { Label("Create Invoice", systemImage: "doc.badge.plus") }
                        Button { showingBulkGenerate = true } label: { Label("Generate Monthly Invoices", systemImage: "doc.on.doc") }
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingNewInvoice) { ManualInvoiceView() }
            .sheet(isPresented: $showingBulkGenerate) { BulkInvoiceGeneratorView() }
        }
    }
}

struct InvoiceRow: View {
    @EnvironmentObject private var store: AspireStore
    var invoice: Invoice

    private var displayStatus: String {
        invoice.isOverdue() ? "Overdue \(invoice.overdueDays())d" : invoice.status.title
    }

    private var statusColor: Color {
        if invoice.isOverdue() { return .red }
        switch invoice.status {
        case .draft: return .secondary
        case .sent: return .blue
        case .partial: return .orange
        case .paid: return .aspireGreen
        case .void: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(statusColor.opacity(0.12))
                Image(systemName: invoice.status == .paid ? "checkmark.seal.fill" : "doc.text.fill").foregroundStyle(statusColor)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(store.customer(id: invoice.customerID)?.name ?? "Unknown Customer").font(.headline)
                Text(invoice.number).font(.caption.monospaced()).foregroundStyle(.secondary)
                Text("Due \(DateFormatter.shortDate.string(from: invoice.dueDate))").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(store.currency(invoice.total)).font(.subheadline.weight(.bold))
                Text(displayStatus)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(statusColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(statusColor)
            }
        }
        .padding(.vertical, 3)
    }
}

struct QuickInvoiceView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    let customer: Customer
    @State private var month = Date()
    @State private var amount: Double

    init(customer: Customer) {
        self.customer = customer
        _amount = State(initialValue: customer.monthlyRate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(customer.name) {
                    DatePicker("Service month", selection: $month, displayedComponents: .date)
                    TextField("Invoice amount", value: $amount, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad)
                }
                Section {
                    Text("The invoice will use the company payment terms and the monthly garden-maintenance description.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Create Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        _ = store.createMonthlyInvoice(for: customer, serviceMonth: month, customAmount: amount)
                        dismiss()
                    }.disabled(amount <= 0)
                }
            }
        }
    }
}

struct ManualInvoiceView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    @State private var customerID: UUID?
    @State private var month = Date()
    @State private var amount = 0.0
    @State private var description = "Garden Maintenance Charges (Monthly)"

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    Picker("Customer", selection: $customerID) {
                        Text("Select customer").tag(UUID?.none)
                        ForEach(store.customers) { customer in Text(customer.name).tag(Optional(customer.id)) }
                    }
                }
                Section("Invoice") {
                    DatePicker("Service month", selection: $month, displayedComponents: .date)
                    TextField("Description", text: $description, axis: .vertical).lineLimit(2...4)
                    TextField("Amount", value: $amount, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad)
                }
            }
            .navigationTitle("New Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }.disabled(customerID == nil || amount <= 0)
                }
            }
            .onChange(of: customerID) { id in
                if let id, let customer = store.customer(id: id), amount == 0 { amount = customer.monthlyRate }
            }
        }
    }

    private func create() {
        guard let customerID, let customer = store.customer(id: customerID) else { return }
        var invoice = store.createMonthlyInvoice(for: customer, serviceMonth: month, customAmount: amount)
        invoice.lineItems = [InvoiceLineItem(description: description, quantity: 1, unitPrice: amount)]
        store.updateInvoice(invoice)
        dismiss()
    }
}

struct BulkInvoiceGeneratorView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    @State private var month = Date()
    @State private var generatedCount: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section("Monthly Billing") {
                    DatePicker("Service month", selection: $month, displayedComponents: .date)
                    LabeledContent("Active customers", value: "\(store.activeCustomers.count)")
                }
                Section {
                    Text("One invoice will be created for each active customer that does not already have an invoice for the selected service month.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let generatedCount {
                    Section { Label("Generated \(generatedCount) new invoice(s)", systemImage: "checkmark.circle.fill").foregroundStyle(Color.aspireGreen) }
                }
            }
            .navigationTitle("Generate Invoices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") { generatedCount = store.generateMonthlyInvoices(for: month).count }
                        .disabled(store.activeCustomers.isEmpty)
                }
            }
        }
    }
}

struct InvoiceDetailView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    let invoiceID: UUID
    @State private var mailDraft: MailDraft?
    @State private var shareItems: ShareItems?
    @State private var showingPayment = false
    @State private var showingDelete = false
    @State private var sending = false
    @State private var resultMessage: String?

    var body: some View {
        Group {
            if let invoice = store.invoice(id: invoiceID), let customer = store.customer(id: invoice.customerID) {
                ScrollView {
                    VStack(spacing: 16) {
                        invoiceHeader(invoice: invoice, customer: customer)
                        invoiceItems(invoice: invoice)
                        paymentSummary(invoice: invoice)
                        actionButtons(invoice: invoice, customer: customer)
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle(invoice.number)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button(role: .destructive) { showingDelete = true } label: { Label("Delete Invoice", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
                .sheet(item: $mailDraft) { draft in
                    MailComposer(draft: draft) { result in
                        if result == .sent { store.markInvoiceSent(invoice.id); resultMessage = "Invoice sent using Apple Mail." }
                    }
                }
                .sheet(item: $shareItems) { payload in ShareSheet(items: payload.items) }
                .sheet(isPresented: $showingPayment) { PaymentEntryView(invoice: invoice) }
                .confirmationDialog("Delete this invoice?", isPresented: $showingDelete, titleVisibility: .visible) {
                    Button("Delete Invoice", role: .destructive) { store.deleteInvoice(invoice.id); dismiss() }
                }
                .alert("Invoice", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: { Text(resultMessage ?? "") }
            } else {
                FullEmptyView(title: "Invoice Not Found", icon: "doc.badge.exclamationmark", message: "The invoice record is no longer available.")
            }
        }
    }

    private func invoiceHeader(invoice: Invoice, customer: Customer) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(customer.name).font(.title3.bold())
                    Text(DateFormatter.monthAndYear.string(from: invoice.serviceMonth)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(store.currency(invoice.total)).font(.title2.bold()).foregroundStyle(Color.aspireGreen)
                    Text(invoice.isOverdue() ? "OVERDUE" : invoice.status.title.uppercased())
                        .font(.caption.weight(.heavy)).foregroundStyle(invoice.isOverdue() ? .red : Color.aspireGreen)
                }
            }
            Divider()
            HStack {
                LabeledContent("Issue", value: DateFormatter.shortDate.string(from: invoice.issueDate))
                Spacer()
                LabeledContent("Due", value: DateFormatter.shortDate.string(from: invoice.dueDate))
            }
            .font(.caption)
        }
        .aspirePanel()
    }

    private func invoiceItems(invoice: Invoice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Invoice Items", subtitle: nil)
            ForEach(invoice.lineItems) { item in
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text(item.description).font(.subheadline.weight(.semibold))
                        Text("\(item.quantity, specifier: "%.2f") × \(store.currency(item.unitPrice))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(store.currency(item.amount)).font(.subheadline.weight(.bold))
                }
            }
        }
        .aspirePanel()
    }

    private func paymentSummary(invoice: Invoice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Payment", subtitle: invoice.notes)
            LabeledContent("Invoice total", value: store.currency(invoice.total))
            LabeledContent("Paid", value: store.currency(invoice.amountPaid))
            LabeledContent("Outstanding", value: store.currency(invoice.outstanding)).font(.headline)
        }
        .aspirePanel()
    }

    private func actionButtons(invoice: Invoice, customer: Customer) -> some View {
        VStack(spacing: 10) {
            ActionButton(title: sending ? "Sending…" : "Send Invoice", icon: "paperplane.fill", style: .green) {
                Task { await sendInvoice(invoice: invoice, customer: customer) }
            }
            .disabled(sending || customer.email.isEmpty)

            HStack(spacing: 10) {
                ActionButton(title: "Share PDF", icon: "square.and.arrow.up", style: .neutral) { sharePDF(invoice: invoice, customer: customer) }
                ActionButton(title: "Record Payment", icon: "banknote.fill", style: .gold) { showingPayment = true }
                    .disabled(invoice.status == .paid || invoice.status == .void)
            }
        }
    }

    private func pdf(invoice: Invoice, customer: Customer) -> Data {
        InvoicePDFService().makePDF(invoice: invoice, customer: customer, company: store.company)
    }

    private func emailBody(invoice: Invoice, customer: Customer) -> String {
        """
        Dear \(customer.name),

        Please find attached invoice \(invoice.number) for \(DateFormatter.monthAndYear.string(from: invoice.serviceMonth)) garden maintenance services.

        Invoice total: \(store.currency(invoice.total))
        Due date: \(DateFormatter.shortDate.string(from: invoice.dueDate))

        \(store.emailConfiguration.signature)
        """
    }

    private func sendInvoice(invoice: Invoice, customer: Customer) async {
        let data = pdf(invoice: invoice, customer: customer)
        let fileName = "\(invoice.number).pdf"
        let subject = "Aspire Garden Invoice \(invoice.number)"
        let body = emailBody(invoice: invoice, customer: customer)
        let config = store.emailConfiguration

        if config.preferredMode == .gmailDirect {
            sending = true
            do {
                let message = try await DirectEmailService().send(
                    recipient: customer.email,
                    subject: subject,
                    body: body,
                    attachments: [DirectEmailAttachment(fileName: fileName, mimeType: "application/pdf", data: data)],
                    configuration: config,
                    apiKey: SecureStore.load(account: "scheduler-api-key")
                )
                store.markInvoiceSent(invoice.id)
                resultMessage = message
            } catch {
                resultMessage = error.localizedDescription
            }
            sending = false
        } else if MFMailComposeViewController.canSendMail() {
            mailDraft = MailDraft(recipient: customer.email, subject: subject, body: body, attachmentData: data, attachmentName: fileName)
        } else {
            do {
                let url = try TemporaryFileService.write(data: data, fileName: fileName)
                shareItems = ShareItems(items: [body, url])
                resultMessage = "Apple Mail is unavailable. The iOS share sheet was opened instead."
            } catch {
                resultMessage = error.localizedDescription
            }
        }
    }

    private func sharePDF(invoice: Invoice, customer: Customer) {
        do {
            let url = try TemporaryFileService.write(data: pdf(invoice: invoice, customer: customer), fileName: "\(invoice.number).pdf")
            shareItems = ShareItems(items: [url])
        } catch {
            resultMessage = error.localizedDescription
        }
    }
}

struct PaymentEntryView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    let invoice: Invoice
    @State private var amount: Double
    @State private var date = Date()

    init(invoice: Invoice) {
        self.invoice = invoice
        _amount = State(initialValue: invoice.outstanding)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(invoice.number) {
                    LabeledContent("Outstanding", value: CurrencyFormatter.string(invoice.outstanding, code: "AED"))
                    TextField("Payment amount", value: $amount, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad)
                    DatePicker("Payment date", selection: $date, displayedComponents: .date)
                }
            }
            .navigationTitle("Record Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.recordPayment(invoiceID: invoice.id, amount: amount, paymentDate: date); dismiss() }
                        .disabled(amount <= 0)
                }
            }
        }
    }
}

// MARK: - Finance

struct FinanceView: View {
    @EnvironmentObject private var store: AspireStore
    @State private var month = Date()
    @State private var showingExpense = false

    private var monthExpenses: [Expense] {
        store.expenses.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    MonthPicker(month: $month)
                    let income = store.invoicedIncome(in: month)
                    let costs = store.expensesTotal(in: month)
                    let profit = income - costs

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Profit & Loss", subtitle: DateFormatter.monthAndYear.string(from: month))
                        FinanceLine(title: "Invoice Income", amount: income, store: store)
                        FinanceLine(title: "Expenses", amount: -costs, store: store)
                        Divider()
                        FinanceLine(title: profit >= 0 ? "Net Profit" : "Net Loss", amount: profit, store: store, emphasized: true)
                    }
                    .aspirePanel()

                    AgingView(summary: store.agingSummary())

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionHeader(title: "Expenses", subtitle: "Fuel and company costs")
                            Spacer()
                            Button { showingExpense = true } label: { Label("Add", systemImage: "plus") }.buttonStyle(.borderedProminent).tint(.aspireGreen)
                        }
                        if monthExpenses.isEmpty {
                            EmptyInlineView(icon: "fuelpump", text: "No expenses recorded for this month")
                        } else {
                            ForEach(monthExpenses) { expense in
                                ExpenseRow(expense: expense)
                                if expense.id != monthExpenses.last?.id { Divider() }
                            }
                        }
                    }
                    .aspirePanel()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Finance")
            .sheet(isPresented: $showingExpense) { ExpenseEditorView() }
        }
    }
}

struct AgingView: View {
    @EnvironmentObject private var store: AspireStore
    var summary: AgingSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Receivables Aging", subtitle: "Unpaid customer invoices")
            AgingRow(label: "Current / Not Due", amount: summary.current)
            AgingRow(label: "1–30 Days", amount: summary.days1To30)
            AgingRow(label: "31–60 Days", amount: summary.days31To60)
            AgingRow(label: "61–90 Days", amount: summary.days61To90)
            AgingRow(label: "Over 90 Days", amount: summary.over90, warning: summary.over90 > 0)
            Divider()
            AgingRow(label: "Total Receivables", amount: summary.total, emphasized: true)
        }
        .aspirePanel()
    }
}

struct ExpenseRow: View {
    @EnvironmentObject private var store: AspireStore
    var expense: Expense

    var body: some View {
        HStack {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Color.aspireGold.opacity(0.15))
                Image(systemName: expense.category == .fuel ? "fuelpump.fill" : "receipt.fill").foregroundStyle(Color.aspireGold)
            }.frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.vendor.isEmpty ? expense.category.rawValue : expense.vendor).font(.subheadline.weight(.semibold))
                Text("\(expense.category.rawValue) • \(DateFormatter.shortDate.string(from: expense.date))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(store.currency(expense.amount)).font(.subheadline.weight(.bold))
        }
    }
}

struct ExpenseEditorView: View {
    @EnvironmentObject private var store: AspireStore
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var category: ExpenseCategory = .fuel
    @State private var vendor = ""
    @State private var amount = 0.0
    @State private var paymentAccount = "Cash"
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Expense") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Category", selection: $category) { ForEach(ExpenseCategory.allCases) { Text($0.rawValue).tag($0) } }
                    TextField("Vendor / payee", text: $vendor)
                    TextField("Amount", value: $amount, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad)
                    TextField("Paid from", text: $paymentAccount)
                }
                Section("Notes") { TextField("Description or receipt reference", text: $notes, axis: .vertical).lineLimit(2...5) }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.addExpense(Expense(date: date, category: category, vendor: vendor, amount: amount, paymentAccount: paymentAccount, notes: notes))
                        dismiss()
                    }.disabled(amount <= 0)
                }
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var store: AspireStore
    @State private var company = CompanyProfile.aspireDefault
    @State private var emailConfig = EmailConfiguration.aspireDefault
    @State private var apiKey = ""
    @State private var isConnecting = false
    @State private var message: String?
    @State private var shareItems: ShareItems?
    @State private var importing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Company Identity") {
                    TextField("Full legal company name", text: $company.fullName, axis: .vertical)
                    TextField("Trading name", text: $company.tradingName)
                    TextField("Address", text: $company.address, axis: .vertical)
                    TextField("Phone", text: $company.phone)
                    TextField("Company email", text: $company.email).textInputAutocapitalization(.never)
                    TextField("Website", text: $company.website).textInputAutocapitalization(.never)
                    TextField("TRN / Tax number", text: $company.taxRegistrationNumber)
                }

                Section("Invoice & Bank Details") {
                    TextField("Invoice prefix", text: $company.invoicePrefix)
                    TextField("Currency", text: $company.currencyCode)
                    Stepper("Payment terms: \(company.paymentTermsDays) days", value: $company.paymentTermsDays, in: 0...90)
                    Stepper("Long overdue alert: \(company.longOverdueDays) days", value: $company.longOverdueDays, in: 7...180)
                    TextField("Bank name", text: $company.bankName)
                    TextField("Account holder", text: $company.accountHolderName)
                    TextField("Account number", text: $company.accountNumber)
                    TextField("IBAN", text: $company.iban).textInputAutocapitalization(.characters)
                    TextField("SWIFT", text: $company.swiftCode).textInputAutocapitalization(.characters)
                    TextField("Invoice terms", text: $company.invoiceTerms, axis: .vertical).lineLimit(2...5)
                }

                Section("Invoice Email Delivery") {
                    Picker("Preferred method", selection: $emailConfig.preferredMode) {
                        ForEach(EmailDeliveryMode.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Scheduler HTTPS URL", text: $emailConfig.schedulerEndpoint).textInputAutocapitalization(.never).keyboardType(.URL)
                    SecureField("Scheduler API key", text: $apiKey)
                    TextField("Email signature", text: $emailConfig.signature, axis: .vertical).lineLimit(3...6)

                    if emailConfig.connectorID.isEmpty {
                        Button {
                            connectGmail()
                        } label: {
                            Label(isConnecting ? "Connecting…" : "Connect Gmail", systemImage: "envelope.badge")
                        }
                        .disabled(isConnecting || emailConfig.schedulerEndpoint.isEmpty || apiKey.isEmpty)
                    } else {
                        LabeledContent("Connected account", value: emailConfig.connectedEmail)
                        Button("Disconnect Gmail", role: .destructive) { disconnectGmail() }
                    }

                    Text("Gmail Direct uses the same scheduler/connector approach as Next Job. Apple Mail Assisted opens the standard iOS mail composer for confirmation.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Alerts & Data") {
                    Button { Task { await store.requestNotificationsAndRefresh() } } label: { Label("Enable Overdue Alerts", systemImage: "bell.badge.fill") }
                    Button { exportBackup() } label: { Label("Export Complete Backup", systemImage: "square.and.arrow.up") }
                    Button { importing = true } label: { Label("Import Backup", systemImage: "square.and.arrow.down") }
                    Button("Add Demo Data for Testing") { store.addDemoData(); message = "Demo customer, invoice and fuel expense added." }
                }

                Section("Application") {
                    LabeledContent("Name", value: "Aspire Maintenance")
                    LabeledContent("Company", value: "Aspire Green Garden Designing and Works LLC")
                    LabeledContent("Version", value: "1.0.0 Test")
                    Text("This build is branded only for Aspire. It does not use Next Solution or Bin Noman branding in the app or generated invoices.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Save") { saveSettings() } }
            }
            .onAppear {
                company = store.company
                emailConfig = store.emailConfiguration
                apiKey = SecureStore.load(account: "scheduler-api-key")
            }
            .sheet(item: $shareItems) { payload in ShareSheet(items: payload.items) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    try store.importData(Data(contentsOf: url))
                    company = store.company
                    emailConfig = store.emailConfiguration
                    message = "Backup imported successfully."
                } catch {
                    message = error.localizedDescription
                }
            }
            .alert("Aspire Maintenance", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(message ?? "") }
        }
    }

    private func saveSettings() {
        store.updateCompany(company)
        store.updateEmailConfiguration(emailConfig)
        do {
            if apiKey.isEmpty { SecureStore.delete(account: "scheduler-api-key") }
            else { try SecureStore.save(apiKey, account: "scheduler-api-key") }
            message = "Company, invoice and email settings saved."
        } catch {
            message = error.localizedDescription
        }
    }

    private func connectGmail() {
        saveSettings()
        isConnecting = true
        Task {
            do {
                let record = try await GmailOAuthClient.shared.connect(configuration: emailConfig, apiKey: apiKey)
                emailConfig.connectorID = record.connectorID
                emailConfig.connectedEmail = record.emailAddress
                store.updateEmailConfiguration(emailConfig)
                message = "Gmail connected: \(record.emailAddress)"
            } catch {
                message = error.localizedDescription
            }
            isConnecting = false
        }
    }

    private func disconnectGmail() {
        isConnecting = true
        Task {
            do {
                try await GmailOAuthClient.shared.disconnect(configuration: emailConfig, apiKey: apiKey)
                emailConfig.connectorID = ""
                emailConfig.connectedEmail = ""
                store.updateEmailConfiguration(emailConfig)
                message = "Gmail disconnected."
            } catch {
                message = error.localizedDescription
            }
            isConnecting = false
        }
    }

    private func exportBackup() {
        do {
            let data = try store.exportData()
            let url = try TemporaryFileService.write(data: data, fileName: "Aspire-Maintenance-Backup-\(DateFormatter.invoiceMonth.string(from: Date())).json")
            shareItems = ShareItems(items: [url])
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Shared Components

struct AspireHeaderCard: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.aspireGreen, lineWidth: 4)
                Text("a").font(.system(size: 42, weight: .bold)).foregroundStyle(Color.aspireGreen)
                Image(systemName: "leaf.fill").font(.caption).foregroundStyle(Color.aspireGold).offset(x: 14, y: -12)
            }
            .frame(width: 68, height: 68)
            VStack(alignment: .leading, spacing: 3) {
                Text("ASPIRE GARDEN").font(.title3.weight(.heavy)).foregroundStyle(Color.aspireGreen)
                Text("Garden Maintenance • Customers • Invoices • Profit & Loss")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .aspirePanel()
    }
}

struct MonthPicker: View {
    @Binding var month: Date

    var body: some View {
        HStack {
            Button { month = Calendar.current.addingMonths(-1, to: month) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(DateFormatter.monthAndYear.string(from: month)).font(.headline)
            Spacer()
            Button { month = Calendar.current.addingMonths(1, to: month) } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.bordered)
        .tint(.aspireGreen)
        .aspirePanel()
    }
}

struct SummaryCard: View {
    var title: String
    var value: String
    var subtitle: String
    var icon: String
    var emphasized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: icon).foregroundStyle(emphasized ? Color.aspireGold : Color.aspireGreen)
                Spacer()
            }
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.subheadline.weight(.semibold))
            Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(emphasized ? Color.aspireGreen.opacity(0.09) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(emphasized ? Color.aspireGreen.opacity(0.25) : Color.clear, lineWidth: 1))
    }
}

struct SectionHeader: View {
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let subtitle, !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct MetricPill: View {
    var title: String
    var value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.65)
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct FullEmptyView: View {
    var title: String
    var icon: String
    var message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 42)).foregroundStyle(Color.aspireGreen)
            Text(title).font(.title3.bold())
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

struct EmptyInlineView: View {
    var icon: String
    var text: String
    var body: some View {
        HStack { Image(systemName: icon).foregroundStyle(Color.aspireGreen); Text(text).font(.subheadline).foregroundStyle(.secondary); Spacer() }
        .padding(.vertical, 8)
    }
}

struct LabeledValue: View {
    var icon: String
    var value: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) { Image(systemName: icon).foregroundStyle(Color.aspireGreen).frame(width: 20); Text(value).font(.subheadline); Spacer() }
    }
}

struct FinanceLine: View {
    var title: String
    var amount: Double
    var store: AspireStore
    var emphasized = false
    var body: some View {
        HStack {
            Text(title).font(emphasized ? .headline : .body)
            Spacer()
            Text(store.currency(amount)).font(emphasized ? .headline : .body).foregroundStyle(amount < 0 ? .red : (emphasized ? Color.aspireGreen : .primary))
        }
    }
}

struct AgingRow: View {
    @EnvironmentObject private var store: AspireStore
    var label: String
    var amount: Double
    var warning = false
    var emphasized = false
    var body: some View {
        HStack {
            Text(label).font(emphasized ? .headline : .subheadline)
            Spacer()
            Text(store.currency(amount)).font(emphasized ? .headline : .subheadline.weight(.semibold)).foregroundStyle(warning ? .red : .primary)
        }
    }
}

enum ActionButtonStyle { case green, gold, neutral }

struct ActionButton: View {
    var title: String
    var icon: String
    var style: ActionButtonStyle
    var action: () -> Void

    private var foreground: Color {
        switch style { case .green: return .white; case .gold: return .black; case .neutral: return .primary }
    }
    private var background: Color {
        switch style { case .green: return .aspireGreen; case .gold: return .aspireGold; case .neutral: return Color(.secondarySystemGroupedBackground) }
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(background, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(foreground)
        }
        .buttonStyle(.plain)
    }
}

struct ShareItems: Identifiable {
    let id = UUID()
    var items: [Any]
}

extension View {
    func aspirePanel() -> some View {
        self.padding().background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension Color {
    static let aspireGreen = Color(red: 0.10, green: 0.48, blue: 0.29)
    static let aspireGold = Color(red: 0.91, green: 0.63, blue: 0.15)
}
