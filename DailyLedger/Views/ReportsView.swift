import Charts
import SwiftUI

private enum ReportPeriod: String, CaseIterable, Identifiable {
    case day = "Daily"
    case month = "Monthly"
    case year = "Yearly"
    case custom = "Custom"
    var id: String { rawValue }
}

private enum ReportKind: String, CaseIterable, Identifiable {
    case summary = "Financial Summary"
    case income = "Income Report"
    case expenses = "Expense Report"
    case loans = "Loans / Transfers"
    case categories = "Category Report"

    var id: String { rawValue }
    var subtitle: String {
        switch self {
        case .summary: return "Income, expenses, transfers and net result"
        case .income: return "All money received in the selected period"
        case .expenses: return "All expenses with transaction snapshots"
        case .loans: return "Amounts transferred out during the selected period"
        case .categories: return "Spending grouped by category"
        }
    }
    var icon: String {
        switch self {
        case .summary: return "chart.bar.xaxis"
        case .income: return "arrow.down.left.circle.fill"
        case .expenses: return "arrow.up.right.circle.fill"
        case .loans: return "arrow.left.arrow.right.circle.fill"
        case .categories: return "square.grid.2x2.fill"
        }
    }
}

private struct ReportBucket: Identifiable {
    let id: String
    let label: String
    let income: Double
    let expense: Double
}

private struct CategoryTotal: Identifiable {
    let id: String
    let name: String
    let amount: Decimal
}

private struct NatureCurrencyBalance: Identifiable {
    let currency: String
    let amount: Decimal
    var id: String { currency }
}

private struct FinanceSummaryCustomCard: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var currencyCode: String
    var accountIDs: [UUID]
    var balanceMode: String?
    var balanceDate: Date?

    init(
        id: UUID = UUID(),
        title: String = "",
        currencyCode: String,
        accountIDs: [UUID] = [],
        balanceMode: String? = FinanceSummaryBalanceMode.current.rawValue,
        balanceDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.currencyCode = currencyCode
        self.accountIDs = accountIDs
        self.balanceMode = balanceMode
        self.balanceDate = balanceDate
    }
}

private enum FinanceSummaryBalanceMode: String, CaseIterable, Identifiable {
    case current
    case closingDate
    case reportPeriodEnd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .current: return "Current"
        case .closingDate: return "Closing Date"
        case .reportPeriodEnd: return "Report End"
        }
    }
}

private enum FinanceSummaryCardStorage {
    static func decode(_ value: String) -> [FinanceSummaryCustomCard] {
        guard let data = value.data(using: .utf8),
              let cards = try? JSONDecoder().decode([FinanceSummaryCustomCard].self, from: data) else {
            return []
        }
        return cards
    }

    static func encode(_ cards: [FinanceSummaryCustomCard]) -> String {
        guard let data = try? JSONEncoder().encode(cards),
              let value = String(data: data, encoding: .utf8) else { return "[]" }
        return value
    }
}

private enum ClosingBalanceAccountStorage {
    static func decode(_ value: String) -> [UUID] {
        guard let data = value.data(using: .utf8),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else { return [] }
        return ids
    }

    static func encode(_ ids: [UUID]) -> String {
        guard let data = try? JSONEncoder().encode(ids),
              let value = String(data: data, encoding: .utf8) else { return "[]" }
        return value
    }
}

struct ReportsView: View {
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Planning & Comparison") {
                    NavigationLink { ChartOfAccountsView() } label: {
                        Label("Chart of Accounts", systemImage: "list.bullet.rectangle.portrait.fill")
                    }
                    NavigationLink { ReportComparisonView() } label: {
                        Label("Compare Reports", systemImage: "chart.xyaxis.line")
                    }
                    NavigationLink { BudgetConsumptionReportView() } label: {
                        Label("Budget Consumption", systemImage: "chart.bar.doc.horizontal")
                    }
                    NavigationLink { BudgetPlannerView() } label: {
                        Label("Budget Suggestions", systemImage: "wand.and.stars")
                    }
                    NavigationLink { CustomAccountReportView() } label: {
                        Label("Custom Account Report", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink { LoanMovementReportView() } label: {
                        Label("Loan Movement by Currency", systemImage: "banknote.fill")
                    }
                    NavigationLink { AccountNatureReportView() } label: {
                        Label("Account Nature Report", systemImage: "folder.badge.gearshape")
                    }
                    NavigationLink { BalanceReconciliationReportView() } label: {
                        Label("Books vs Message Balance", systemImage: "checkmark.arrow.trianglehead.counterclockwise")
                    }
                }
                Section {
                    ForEach(filteredReportKinds) { kind in
                        NavigationLink {
                            ReportDetailView(kind: kind)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(kind.rawValue).font(.headline)
                                    Text(kind.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: kind.icon)
                                    .foregroundStyle(AppTheme.purple)
                            }
                            .padding(.vertical, 5)
                        }
                    }
                } header: {
                    Text("Choose a report")
                } footer: {
                    Text("Select a report first, then choose its month or year.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Reports")
            .searchable(text: $searchText, prompt: "Search reports")
        }
    }

    private var filteredReportKinds: [ReportKind] {
        guard !searchText.isEmpty else { return ReportKind.allCases }
        return ReportKind.allCases.filter {
            $0.rawValue.localizedCaseInsensitiveContains(searchText) ||
            $0.subtitle.localizedCaseInsensitiveContains(searchText)
        }
    }
}

private struct ReportComparisonView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var period: ReportPeriod = .month
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEnd = Date()

    var body: some View {
        List {
            Picker("Period", selection: $period) {
                ForEach(ReportPeriod.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu)
            if period == .custom {
                Section("Custom Dates") {
                    DatePicker("From", selection: $customStart, displayedComponents: .date)
                    DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date)
                }
            }
            Section("Current vs Previous") {
                comparisonHeader
                comparisonRow("Current", interval: currentInterval)
                comparisonRow("Previous", interval: previousInterval)
                comparisonValues(
                    title: "Change",
                    income: amount(.income, in: currentInterval) - amount(.income, in: previousInterval),
                    expense: amount(.expense, in: currentInterval) - amount(.expense, in: previousInterval)
                )
            }
        }
        .navigationTitle("Compare Reports")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var calendarUnit: Calendar.Component {
        switch period { case .day: return .day; case .year: return .year; default: return .month }
    }
    private var currentInterval: DateInterval {
        if period == .custom {
            return DateInterval(
                start: Calendar.current.startOfDay(for: customStart),
                end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: customEnd))!
            )
        }
        return Calendar.current.dateInterval(of: calendarUnit, for: Date())!
    }
    private var previousInterval: DateInterval {
        if period == .custom {
            let duration = currentInterval.duration
            return DateInterval(start: currentInterval.start.addingTimeInterval(-duration), end: currentInterval.start)
        }
        let date = Calendar.current.date(byAdding: calendarUnit, value: -1, to: Date())!
        return Calendar.current.dateInterval(of: calendarUnit, for: date)!
    }
    private func amount(_ type: TransactionType, in interval: DateInterval) -> Decimal {
        store.transactions.lazy.filter {
            guard interval.contains($0.date) else { return false }
            if type == .income {
                return store.isReportIncome($0) &&
                    store.account(withID: store.reportIncomeAccountID($0))?.currencyCode == store.currencyCode
            }
            return $0.type == type &&
                store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
        }.reduce(Decimal.zero) {
            $0 + (type == .income ? store.reportIncomeAmount($1) : $1.amount)
        }
    }
    private var comparisonHeader: some View {
        HStack {
            Text("Period").frame(maxWidth: .infinity, alignment: .leading)
            Text("Income").frame(width: 100, alignment: .trailing)
            Text("Expense").frame(width: 100, alignment: .trailing)
        }.font(.caption.bold()).foregroundStyle(.secondary)
    }
    private func comparisonRow(_ title: String, interval: DateInterval) -> some View {
        NavigationLink {
            ComparisonTransactionsView(interval: interval)
        } label: {
            comparisonValues(
                title: "\(title)\n\(transactionCount(in: interval)) trans.",
                income: amount(.income, in: interval),
                expense: amount(.expense, in: interval)
            )
        }
    }
    private func comparisonValues(title: String, income: Decimal, expense: Decimal) -> some View {
        HStack {
            Text(title).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            Text(DisplayFormat.currency(income, code: store.currencyCode))
                .font(.caption.bold()).frame(width: 100, alignment: .trailing)
            Text(DisplayFormat.currency(expense, code: store.currencyCode))
                .font(.caption.bold()).frame(width: 100, alignment: .trailing)
        }.minimumScaleFactor(0.65)
    }
    private func transactionCount(in interval: DateInterval) -> Int {
        store.transactions.lazy.filter {
            guard interval.contains($0.date) else { return false }
            if store.isReportIncome($0) {
                return store.account(withID: store.reportIncomeAccountID($0))?.currencyCode == store.currencyCode
            }
            return $0.type == .expense &&
                store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
        }.count
    }
}

private struct CustomAccountReportView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var selected = Set<UUID>()
    @State private var start = Calendar.current.dateInterval(of: .month, for: Date())!.start
    @State private var end = Date()
    @State private var compare = true
    @State private var initialized = false

    var body: some View {
        List {
            Section("Accounts") {
                HStack {
                    Button("Select All") { selected = Set(store.activeAccounts.map(\.id)) }
                    Spacer()
                    Button("Deselect All") { selected.removeAll() }
                }
                ForEach(store.activeAccounts) { account in
                    HStack {
                        Label(account.name, systemImage: account.icon)
                        Spacer()
                        Image(systemName: selected.contains(account.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(account.id) ? AppTheme.purple : .secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggle(account.id)
                    }
                    .accessibilityAddTraits(selected.contains(account.id) ? .isSelected : [])
                }
            }
            Section("Dates") {
                DatePicker("From", selection: $start, displayedComponents: .date)
                DatePicker("To", selection: $end, in: start..., displayedComponents: .date)
                Toggle("Compare previous period", isOn: $compare)
            }
            Section("Selected Period") {
                accountMetricRow("Income", type: .income, interval: interval)
                accountMetricRow("Expenses", type: .expense, interval: interval)
            }
            if compare {
                Section("Previous Equal Period") {
                    accountMetricRow("Income", type: .income, interval: previousInterval)
                    accountMetricRow("Expenses", type: .expense, interval: previousInterval)
                    LabeledContent("Income change", value: formatted(
                        total(.income, in: interval) - total(.income, in: previousInterval)
                    ))
                    LabeledContent("Expense change", value: formatted(
                        total(.expense, in: interval) - total(.expense, in: previousInterval)
                    ))
                }
            }
        }
        .navigationTitle("Custom Account Report")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !initialized else { return }
            initialized = true
            selected = Set(store.activeAccounts.map(\.id))
        }
    }

    private func accountMetricRow(_ title: String, type: TransactionType, interval: DateInterval) -> some View {
        NavigationLink {
            AccountReportTransactionsView(interval: interval, accountIDs: selected, type: type)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text("\(matchingTransactions(type, in: interval).count) transactions")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(formatted(total(type, in: interval))).font(.subheadline.bold())
            }
        }
    }

    private var interval: DateInterval {
        DateInterval(start: Calendar.current.startOfDay(for: start),
                     end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end))!)
    }
    private var previousInterval: DateInterval {
        DateInterval(start: interval.start.addingTimeInterval(-interval.duration), end: interval.start)
    }
    private func transactions(in interval: DateInterval) -> [LedgerTransaction] {
        store.transactions.filter { interval.contains($0.date) }
    }
    private func matchingTransactions(_ type: TransactionType, in interval: DateInterval) -> [LedgerTransaction] {
        transactions(in: interval).filter {
            if type == .income {
                return store.isReportIncome($0) &&
                    selected.contains(store.reportIncomeAccountID($0) ?? LedgerAccount.legacyMainID)
            }
            return $0.type == type && selected.contains($0.accountID ?? LedgerAccount.legacyMainID)
        }
    }
    private func total(_ type: TransactionType, in interval: DateInterval) -> Decimal {
        matchingTransactions(type, in: interval).reduce(0) {
            $0 + (type == .income ? store.reportIncomeAmount($1) : $1.amount)
        }
    }
    private func formatted(_ value: Decimal) -> String { DisplayFormat.currency(value, code: store.currencyCode) }
    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
}

private struct LoanMovementReportView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var month = Date()
    @AppStorage("LoanReportCustomDates") private var customDates = false
    @AppStorage("LoanReportStart") private var storedStart = Calendar.current.dateInterval(of: .month, for: Date())!.start.timeIntervalSince1970
    @AppStorage("LoanReportEnd") private var storedEnd = Date().timeIntervalSince1970

    var body: some View {
        List {
            Section {
                Toggle("Custom Date Range", isOn: $customDates)
                if customDates {
                    DatePicker("From", selection: startBinding, displayedComponents: .date)
                    DatePicker("To", selection: endBinding, in: Date(timeIntervalSince1970: storedStart)..., displayedComponents: .date)
                } else {
                    DatePicker("Month", selection: $month, displayedComponents: [.date])
                        .datePickerStyle(.compact)
                }
            }
            ForEach(currencies, id: \.self) { currency in
                Section(currency) {
                    NavigationLink {
                        LoanTransactionsView(interval: interval, currency: currency, movement: .increased)
                    } label: {
                        LabeledContent("Loan increased", value: DisplayFormat.currency(increased(currency), code: currency))
                    }
                    NavigationLink {
                        LoanTransactionsView(interval: interval, currency: currency, movement: .paid)
                    } label: {
                        LabeledContent("Loan decrease / paid", value: DisplayFormat.currency(paid(currency), code: currency))
                    }
                    LabeledContent("Net movement", value: DisplayFormat.currency(increased(currency) - paid(currency), code: currency))
                }
            }
        }
        .navigationTitle("Loan Movement")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var interval: DateInterval {
        if customDates {
            let start = Date(timeIntervalSince1970: storedStart)
            let end = Date(timeIntervalSince1970: storedEnd)
            return DateInterval(start: Calendar.current.startOfDay(for: start),
                end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end))!)
        }
        return Calendar.current.dateInterval(of: .month, for: month)!
    }
    private var startBinding: Binding<Date> {
        Binding(get: { Date(timeIntervalSince1970: storedStart) }, set: { storedStart = $0.timeIntervalSince1970 })
    }
    private var endBinding: Binding<Date> {
        Binding(get: { Date(timeIntervalSince1970: storedEnd) }, set: { storedEnd = $0.timeIntervalSince1970 })
    }
    private var loanAccounts: [LedgerAccount] {
        store.accounts.filter { $0.group == .payments || $0.nature == .loan }
    }
    private var currencies: [String] {
        let values = Set(loanAccounts.map(\.currencyCode))
        return values.isEmpty ? ["QAR", "PKR"] : values.sorted()
    }
    private func increased(_ currency: String) -> Decimal {
        let ids = Set(loanAccounts.filter { $0.currencyCode == currency }.map(\.id))
        return store.transactions.filter {
            interval.contains($0.date) &&
            ids.contains($0.accountID ?? LedgerAccount.legacyMainID) &&
            ($0.type == .expense || $0.type == .transfer)
        }.reduce(0) { $0 + $1.amount }
    }
    private func paid(_ currency: String) -> Decimal {
        let ids = Set(loanAccounts.filter { $0.currencyCode == currency }.map(\.id))
        return store.transactions.filter {
            $0.type == .transfer && interval.contains($0.date) && ids.contains($0.destinationAccountID ?? LedgerAccount.legacyMainID)
        }.reduce(0) { total, item in
            total + (item.destinationAmount ?? item.amount)
        }
    }
}

private struct ReportDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    let kind: ReportKind
    @AppStorage("ReportPeriodSelection") private var storedPeriod = ReportPeriod.month.rawValue
    @AppStorage("ReportCustomStart") private var storedCustomStart = Date().timeIntervalSince1970
    @AppStorage("ReportCustomEnd") private var storedCustomEnd = Date().timeIntervalSince1970
    @AppStorage("FinanceSummaryCustomCardsV1") private var storedCustomSummaryCards = "[]"
    @AppStorage("FinanceSummaryQatarClosingAccountsV1") private var storedClosingAccountIDs = "[]"
    @State private var anchorDate = Date()
    @State private var selectedTransaction: LedgerTransaction?
    @State private var showingCustomDates = false
    @State private var draftStartDate = Date()
    @State private var draftEndDate = Date()
    @State private var searchText = ""
    @State private var cachedExpenseTransactions: [LedgerTransaction] = []
    @State private var editingSummaryCard: FinanceSummaryCustomCard?
    @State private var editingClosingBalance = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    Picker("Report period", selection: $storedPeriod) {
                        ForEach(ReportPeriod.allCases) { value in
                            Text(value.rawValue).tag(value.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    periodNavigator
                    if kind == .summary { totalCards }
                    if kind == .summary || kind == .income {
                        activityChart
                    }
                    if kind == .summary || kind == .categories {
                        categoryBreakdown
                    }
                    if kind == .income || kind == .expenses || kind == .loans {
                        transactionList
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(AppTheme.page)
            .navigationTitle(kind.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if kind == .summary {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            editingSummaryCard = FinanceSummaryCustomCard(
                                currencyCode: store.currencyCode
                            )
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .accessibilityLabel("Add custom account balance card")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search report transactions")
            .onAppear(perform: refreshExpenseCache)
            .onChange(of: anchorDate) { _ in refreshExpenseCache() }
            .onChange(of: storedCustomStart) { _ in refreshExpenseCache() }
            .onChange(of: storedCustomEnd) { _ in refreshExpenseCache() }
            .onChange(of: searchText) { _ in refreshExpenseCache() }
            .onChange(of: store.transactions.count) { _ in refreshExpenseCache() }
            .onChange(of: storedPeriod) { value in
                anchorDate = Date()
                if value == ReportPeriod.custom.rawValue {
                    draftStartDate = Date(timeIntervalSince1970: storedCustomStart)
                    draftEndDate = Date(timeIntervalSince1970: storedCustomEnd)
                    showingCustomDates = true
                }
                refreshExpenseCache()
            }
            .sheet(item: $selectedTransaction) { transaction in
                TransactionSnapshotView(transaction: transaction)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showingCustomDates) {
                NavigationStack {
                    Form {
                        DatePicker("From", selection: $draftStartDate, displayedComponents: .date)
                        DatePicker("To", selection: $draftEndDate, displayedComponents: .date)
                    }
                    .navigationTitle("Custom Report Period")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingCustomDates = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                storedCustomStart = draftStartDate.timeIntervalSince1970
                                storedCustomEnd = draftEndDate.timeIntervalSince1970
                                storedPeriod = ReportPeriod.custom.rawValue
                                showingCustomDates = false
                            }
                        }
                    }
                }
            }
            .fullScreenCover(item: $editingSummaryCard) { card in
                NavigationStack {
                    FinanceSummaryCardEditor(
                        card: card,
                        reportPeriodEnd: selectedInterval.end
                    )
                        .environmentObject(store)
                }
            }
            .sheet(isPresented: $editingClosingBalance) {
                NavigationStack {
                    QatarClosingBalanceEditor(
                        storedAccountIDs: $storedClosingAccountIDs
                    )
                    .environmentObject(store)
                }
            }
        }
    }

    private var transactionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind.rawValue)
                .font(.headline)
            if selectedTransactions.isEmpty {
                EmptyLedgerView(
                    title: "No transactions",
                    message: "Nothing is available for this report period."
                )
            } else {
                ForEach(selectedTransactions.sorted { $0.date > $1.date }) { transaction in
                    Button {
                        selectedTransaction = transaction
                    } label: {
                        TransactionRow(
                            transaction: transaction,
                            accountID: kind == .income ? store.reportIncomeAccountID(transaction) : nil
                        )
                    }
                    .buttonStyle(.plain)
                    if transaction.id != selectedTransactions.last?.id { Divider() }
                }
                Divider()
                HStack {
                    Text("Total · \(selectedTransactions.count) transactions")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(DisplayFormat.currency(transactionListTotal, code: store.currencyCode))
                        .font(.headline)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var transactionListTotal: Decimal {
        selectedTransactions.reduce(Decimal.zero) {
            $0 + (kind == .income ? store.reportIncomeAmount($1) : $1.amount)
        }
    }

    private var periodNavigator: some View {
        HStack {
            Button { movePeriod(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 40, height: 40)
                    .background(.background, in: Circle())
            }
            .disabled(selectedPeriod == .custom)
            .opacity(selectedPeriod == .custom ? 0.35 : 1)
            Spacer()
            VStack(spacing: 2) {
                Text(periodTitle)
                    .font(.headline)
                Text("\(selectedTransactions.count) transactions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { movePeriod(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 40, height: 40)
                    .background(.background, in: Circle())
            }
            .disabled(isCurrentPeriod || selectedPeriod == .custom)
            .opacity(isCurrentPeriod || selectedPeriod == .custom ? 0.35 : 1)
        }
    }

    private var totalCards: some View {
        VStack(spacing: 16) {
            ReportTotalCard(
                title: "Net Balance",
                value: financeSummaryNetBalance,
                currencyCode: store.currencyCode,
                icon: "equal.circle.fill",
                color: financeSummaryNetBalance >= 0 ? AppTheme.purple : AppTheme.red,
                secondaryText: closingBalanceAccounts.isEmpty
                    ? nil
                    : "Includes opening balance: \(DisplayFormat.currency(qatarClosingBalance, code: "QAR"))"
            )
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(financeSummaryNetBalance >= 0 ? AppTheme.purple : AppTheme.red, lineWidth: 2.5)
            }
            Text("PKR loan movement converted at fixed rate: PKR 77 = QAR 1.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            SummaryConnectorLines()
                .frame(height: 38)
                .padding(.horizontal, 46)
                .accessibilityHidden(true)
            HStack(alignment: .top, spacing: 12) {
                summaryColumn(
                    title: "Added",
                    color: AppTheme.green,
                    primaryTitle: "Income",
                    primaryValue: totals.income,
                    primaryKind: .income,
                    movements: loanIncreaseMovements
                )
                summaryColumn(
                    title: "Deducted",
                    color: AppTheme.red,
                    primaryTitle: "Expenses",
                    primaryValue: totals.expense,
                    primaryKind: .expenses,
                    movements: loanDecreaseMovements
                )
            }

            HStack {
                Rectangle().frame(height: 2).foregroundStyle(AppTheme.purple)
                Text("Opening Balance")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.purple)
                Rectangle().frame(height: 2).foregroundStyle(AppTheme.purple)
            }
            .padding(.top, 2)

            ForEach(customSummaryCards) { card in
                let accountCount = validAccountCount(card)
                let timingLabel = customSummaryTimingLabel(card)
                HStack(spacing: 8) {
                    Button {
                        editingSummaryCard = card
                    } label: {
                        FinanceSummaryBalanceCard(
                            title: customSummaryTitle(card),
                            value: customSummaryBalance(card),
                            currencyCode: card.currencyCode,
                            accountCount: accountCount,
                            timingLabel: timingLabel
                        )
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Button {
                            editingSummaryCard = card
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            deleteCustomSummaryCard(card.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title2)
                            .frame(width: 42, height: 42)
                    }
                    .accessibilityLabel("Options for \(customSummaryTitle(card))")
                }
            }

            Button {
                editingClosingBalance = true
            } label: {
                ReportTotalCard(
                    title: "Opening Balance as of \(selectedInterval.start.formatted(date: .abbreviated, time: .omitted))",
                    value: qatarClosingBalance,
                    currencyCode: "QAR",
                    icon: "calendar.badge.clock",
                    color: AppTheme.purple,
                    secondaryText: closingBalanceAccounts.isEmpty
                        ? "Select Qatar accounts"
                        : closingBalanceAccounts.map(\.name).joined(separator: " + ")
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .stroke(AppTheme.purple, lineWidth: 2.5)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit Qatar opening balance accounts")
        }
    }

    private var closingBalanceAccounts: [LedgerAccount] {
        let selected = Set(ClosingBalanceAccountStorage.decode(storedClosingAccountIDs))
        return store.activeAccounts.filter { $0.group == .qatar && selected.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var closingBalanceCutoff: Date {
        selectedInterval.start
    }

    private var qatarClosingBalance: Decimal {
        store.combinedBalance(for: closingBalanceAccounts, before: closingBalanceCutoff)
    }

    private var loanIncreaseMovements: [LoanNetMovement] {
        store.loanNetMovements(in: selectedInterval).filter { $0.netAmount > 0 }
    }

    private var loanDecreaseMovements: [LoanNetMovement] {
        store.loanNetMovements(in: selectedInterval).filter { $0.netAmount < 0 }
    }

    private func summaryColumn(
        title: String,
        color: Color,
        primaryTitle: String,
        primaryValue: Decimal,
        primaryKind: PeriodTransactionKind,
        movements: [LoanNetMovement]
    ) -> some View {
        VStack(spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)

            NavigationLink {
                PeriodTransactionsView(kind: primaryKind, interval: selectedInterval)
            } label: {
                ReportTotalCard(
                    title: primaryTitle,
                    value: primaryValue,
                    currencyCode: store.currencyCode,
                    icon: primaryKind == .income ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill",
                    color: color,
                    compact: true
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .stroke(color, lineWidth: 2.5)
                }
            }
            .buttonStyle(.plain)

            formulaOperator("+", color: color)

            if movements.isEmpty {
                ReportTotalCard(
                    title: primaryKind == .income ? "Loan Increase" : "Loan Decrease",
                    value: 0,
                    currencyCode: store.currencyCode,
                    icon: primaryKind == .income ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill",
                    color: color,
                    compact: true
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .stroke(color, lineWidth: 2.5)
                }
            } else {
                ForEach(Array(movements.enumerated()), id: \.element.id) { index, movement in
                    if index > 0 { formulaOperator("+", color: color) }
                    NavigationLink { LoanMovementReportView() } label: {
                        ReportTotalCard(
                            title: primaryKind == .income ? "Loan Increase" : "Loan Decrease",
                            value: abs(movement.netAmount),
                            currencyCode: movement.currencyCode,
                            icon: primaryKind == .income ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill",
                            color: color,
                            compact: true,
                            secondaryText: movement.currencyCode.uppercased() == "PKR"
                                ? "QAR: \(DisplayFormat.currency(abs(movement.netAmount) / Decimal(77), code: "QAR"))"
                                : nil
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 19, style: .continuous)
                                .stroke(color, lineWidth: 2.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(color.opacity(0.65), lineWidth: 2)
        }
    }

    private func formulaOperator(_ symbol: String, color: Color) -> some View {
        Text(symbol)
            .font(.title3.bold())
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
            .background(color.opacity(0.12), in: Circle())
            .overlay { Circle().stroke(color, lineWidth: 2) }
    }

    private var customSummaryCards: [FinanceSummaryCustomCard] {
        FinanceSummaryCardStorage.decode(storedCustomSummaryCards)
    }

    private func customSummaryTitle(_ card: FinanceSummaryCustomCard) -> String {
        let title = card.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Selected Account Balance" : title
    }

    private func validAccounts(_ card: FinanceSummaryCustomCard) -> [LedgerAccount] {
        let ids = Set(card.accountIDs)
        return store.accounts.filter {
            ids.contains($0.id) &&
            $0.currencyCode.caseInsensitiveCompare(card.currencyCode) == .orderedSame
        }
    }

    private func validAccountCount(_ card: FinanceSummaryCustomCard) -> Int {
        validAccounts(card).count
    }

    private func customSummaryBalance(_ card: FinanceSummaryCustomCard) -> Decimal {
        store.combinedBalance(
            for: validAccounts(card),
            before: customSummaryCutoff(card)
        )
    }

    private func customSummaryCutoff(_ card: FinanceSummaryCustomCard) -> Date? {
        switch FinanceSummaryBalanceMode(rawValue: card.balanceMode ?? "") ?? .current {
        case .current:
            return nil
        case .closingDate:
            let date = card.balanceDate ?? Date()
            return Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date))
        case .reportPeriodEnd:
            return selectedInterval.end
        }
    }

    private func customSummaryTimingLabel(_ card: FinanceSummaryCustomCard) -> String {
        switch FinanceSummaryBalanceMode(rawValue: card.balanceMode ?? "") ?? .current {
        case .current:
            return "Current balance"
        case .closingDate:
            return "Closing · \((card.balanceDate ?? Date()).formatted(date: .abbreviated, time: .omitted))"
        case .reportPeriodEnd:
            let closingDay = Calendar.current.date(byAdding: .day, value: -1, to: selectedInterval.end) ?? selectedInterval.end
            return "Report closing · \(closingDay.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    private func deleteCustomSummaryCard(_ id: UUID) {
        storedCustomSummaryCards = FinanceSummaryCardStorage.encode(
            customSummaryCards.filter { $0.id != id }
        )
    }

    private var financeSummaryNetBalance: Decimal {
        totals.income + convertedLoanMovement - totals.expense + qatarClosingBalance
    }

    private var convertedLoanMovement: Decimal {
        store.loanNetMovements(in: selectedInterval).reduce(Decimal.zero) {
            result, movement in
            switch movement.currencyCode.uppercased() {
            case "QAR":
                return result + movement.netAmount
            case "PKR":
                return result + movement.netAmount / Decimal(77)
            default:
                return result
            }
        }
    }

    private var activityChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()
                HStack(spacing: 12) {
                    ChartLegend(color: AppTheme.green, title: "Income")
                    ChartLegend(color: AppTheme.red, title: "Expense")
                }
            }

            if buckets.allSatisfy({ $0.income == 0 && $0.expense == 0 }) {
                EmptyLedgerView(
                    title: "Nothing to chart",
                    message: "Transactions in this period will appear here."
                )
            } else {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Period", bucket.label),
                        y: .value("Income", bucket.income)
                    )
                    .foregroundStyle(AppTheme.green.gradient)
                    .position(by: .value("Type", "Income"))
                    .cornerRadius(3)

                    BarMark(
                        x: .value("Period", bucket.label),
                        y: .value("Expense", bucket.expense)
                    )
                    .foregroundStyle(AppTheme.red.gradient)
                    .position(by: .value("Type", "Expense"))
                    .cornerRadius(3)
                }
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 230)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Spending by category")
                .font(.headline)

            if categoryTotals.isEmpty {
                Text("No expenses in this period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ForEach(categoryTotals) { item in
                    NavigationLink {
                        CategoryTransactionsView(
                            category: item.name,
                            interval: selectedInterval
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: AppTheme.categoryIcon(item.name))
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.categoryColor(item.name))
                                .frame(width: 34, height: 34)
                                .background(AppTheme.categoryColor(item.name).opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.name)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(DisplayFormat.currency(item.amount, code: store.currencyCode))
                                        .font(.subheadline.bold())
                                }
                                ProgressView(value: categoryRatio(item.amount))
                                    .tint(AppTheme.categoryColor(item.name))
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Divider()
                HStack {
                    Text("Total Expenses").font(.headline)
                    Spacer()
                    Text(DisplayFormat.currency(totals.expense, code: store.currencyCode))
                        .font(.headline)
                }
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var selectedInterval: DateInterval {
        let calendar = Calendar.current
        if selectedPeriod == .custom {
            let first = Date(timeIntervalSince1970: storedCustomStart)
            let second = Date(timeIntervalSince1970: storedCustomEnd)
            let start = calendar.startOfDay(for: min(first, second))
            let endDay = calendar.startOfDay(for: max(first, second))
            return DateInterval(
                start: start,
                end: calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
            )
        }
        let component: Calendar.Component = selectedPeriod == .day ? .day : (selectedPeriod == .month ? .month : .year)
        return calendar.dateInterval(of: component, for: anchorDate)
            ?? DateInterval(start: anchorDate, duration: 1)
    }

    private var selectedTransactions: [LedgerTransaction] {
        if kind == .expenses { return cachedExpenseTransactions }
        return store.transactions.filter {
            guard selectedInterval.contains($0.date) else { return false }
            let kindMatches: Bool
            switch kind {
            case .summary, .categories:
                kindMatches = store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
            case .income:
                kindMatches = store.isReportIncome($0) &&
                    store.account(withID: store.reportIncomeAccountID($0))?.currencyCode == store.currencyCode
            case .expenses:
                kindMatches = $0.type == .expense &&
                    store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
            case .loans:
                kindMatches = $0.type == .transfer &&
                    store.account(withID: $0.accountID)?.currencyCode == store.currencyCode &&
                    store.account(withID: $0.destinationAccountID)?.group == .payments
            }
            guard kindMatches, !searchText.isEmpty else { return kindMatches }
            return $0.category.localizedCaseInsensitiveContains(searchText) ||
                ($0.vendor?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                $0.details.localizedCaseInsensitiveContains(searchText) ||
                NSDecimalNumber(decimal: $0.amount).stringValue.contains(searchText)
        }
    }

    private func refreshExpenseCache() {
        guard kind == .expenses else { return }
        let interval = selectedInterval
        let accountCurrency = Dictionary(uniqueKeysWithValues: store.accounts.map { ($0.id, $0.currencyCode) })
        let query = searchText
        cachedExpenseTransactions = store.transactions.filter {
            guard $0.type == .expense, interval.contains($0.date),
                  accountCurrency[$0.accountID ?? LedgerAccount.legacyMainID] == store.currencyCode else { return false }
            guard !query.isEmpty else { return true }
            return $0.category.localizedCaseInsensitiveContains(query) ||
                ($0.vendor?.localizedCaseInsensitiveContains(query) ?? false) ||
                $0.details.localizedCaseInsensitiveContains(query) ||
                NSDecimalNumber(decimal: $0.amount).stringValue.contains(query)
        }
    }

    private var totals: LedgerTotals {
        store.totals(in: selectedInterval)
    }

    private var periodTitle: String {
        switch selectedPeriod {
        case .day: return DisplayFormat.day.string(from: anchorDate)
        case .month: return DisplayFormat.monthYear.string(from: anchorDate)
        case .year: return DisplayFormat.year.string(from: anchorDate)
        case .custom:
            return "\(DisplayFormat.day.string(from: selectedInterval.start)) – \(DisplayFormat.day.string(from: selectedInterval.end.addingTimeInterval(-1)))"
        }
    }

    private var isCurrentPeriod: Bool {
        let calendar = Calendar.current
        if selectedPeriod == .day {
            return calendar.isDateInToday(anchorDate)
        }
        if selectedPeriod == .month {
            return calendar.isDate(anchorDate, equalTo: Date(), toGranularity: .month)
        }
        if selectedPeriod == .custom { return true }
        return calendar.isDate(anchorDate, equalTo: Date(), toGranularity: .year)
    }

    private var buckets: [ReportBucket] {
        let calendar = Calendar.current
        if selectedPeriod == .day {
            return makeHourlyBuckets()
        }
        if selectedPeriod == .month || selectedPeriod == .custom {
            if selectedPeriod == .custom {
                let grouped = Dictionary(grouping: selectedTransactions) {
                    calendar.startOfDay(for: $0.date)
                }
                return grouped.keys.sorted().map { date in
                    makeBucket(
                        id: "custom-\(date.timeIntervalSince1970)",
                        label: DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none),
                        items: grouped[date, default: []]
                    )
                }
            }
            let days = calendar.range(of: .day, in: .month, for: anchorDate) ?? 1..<2
            return days.map { day in
                let items = selectedTransactions.filter {
                    calendar.component(.day, from: $0.date) == day
                }
                return makeBucket(id: "day-\(day)", label: "\(day)", items: items)
            }
        }

        let monthSymbols = calendar.shortMonthSymbols
        return (1...12).map { month in
            let items = selectedTransactions.filter {
                calendar.component(.month, from: $0.date) == month
            }
            return makeBucket(
                id: "month-\(month)",
                label: String(monthSymbols[month - 1].prefix(3)),
                items: items
            )
        }
    }

    private var categoryTotals: [CategoryTotal] {
        let expenses = selectedTransactions.filter { $0.type == .expense }
        let grouped = Dictionary(grouping: expenses, by: \.category)
        return grouped.map { category, items in
            CategoryTotal(
                id: category,
                name: category,
                amount: items.reduce(Decimal.zero) { $0 + $1.amount }
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    private func makeBucket(id: String, label: String, items: [LedgerTransaction]) -> ReportBucket {
        let income = items.filter(store.isReportIncome).reduce(Decimal.zero) {
            $0 + store.reportIncomeAmount($1)
        }
        let expense = items.filter { $0.type == .expense }.reduce(Decimal.zero) { $0 + $1.amount }
        return ReportBucket(
            id: id,
            label: label,
            income: NSDecimalNumber(decimal: income).doubleValue,
            expense: NSDecimalNumber(decimal: expense).doubleValue
        )
    }

    private func categoryRatio(_ amount: Decimal) -> Double {
        guard totals.expense > 0 else { return 0 }
        return NSDecimalNumber(decimal: amount / totals.expense).doubleValue
    }

    private func movePeriod(_ direction: Int) {
        guard selectedPeriod != .custom, !(direction > 0 && isCurrentPeriod) else { return }
        let component: Calendar.Component = selectedPeriod == .day ? .day : (selectedPeriod == .month ? .month : .year)
        anchorDate = Calendar.current.date(byAdding: component, value: direction, to: anchorDate) ?? anchorDate
    }

    private func makeHourlyBuckets() -> [ReportBucket] {
        let calendar = Calendar.current
        return stride(from: 0, to: 24, by: 3).map { hour in
            let items = selectedTransactions.filter {
                let value = calendar.component(.hour, from: $0.date)
                return value >= hour && value < hour + 3
            }
            return makeBucket(id: "hour-\(hour)", label: String(format: "%02d:00", hour), items: items)
        }
    }

    private var selectedPeriod: ReportPeriod {
        ReportPeriod(rawValue: storedPeriod) ?? .month
    }
}

private struct ReportTotalCard: View {
    let title: String
    let value: Decimal
    let currencyCode: String
    let icon: String
    let color: Color
    var compact = false
    var secondaryText: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(compact ? .body : .title3)
                .foregroundStyle(color)
                .frame(width: compact ? 35 : 42, height: compact ? 35 : 42)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(DisplayFormat.currency(value, code: currencyCode))
                    .font(compact ? .subheadline.bold() : .title3.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if let secondaryText {
                    Text(secondaryText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(compact ? 13 : 16)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}

private struct FinanceSummaryBalanceCard: View {
    let title: String
    let value: Decimal
    let currencyCode: String
    let accountCount: Int
    let timingLabel: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "wallet.pass.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    LinearGradient(
                        colors: [AppTheme.purple, AppTheme.blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(DisplayFormat.currency(value, code: currencyCode))
                    .font(.title3.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                HStack(spacing: 5) {
                    Label(timingLabel, systemImage: "calendar")
                    Text("·")
                    Text("\(accountCount) account\(accountCount == 1 ? "" : "s")")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.purple)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), AppTheme.purple.opacity(0.055)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 19, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(AppTheme.purple, lineWidth: 2.5)
        }
    }
}

private struct SummaryConnectorLines: View {
    var body: some View {
        GeometryReader { proxy in
            let center = proxy.size.width / 2
            let splitY = proxy.size.height * 0.42
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: center - 2, y: 0))
                    path.addLine(to: CGPoint(x: center - 2, y: splitY))
                    path.addLine(to: CGPoint(x: proxy.size.width * 0.24, y: splitY))
                    path.addLine(to: CGPoint(x: proxy.size.width * 0.24, y: proxy.size.height))
                }
                .stroke(AppTheme.green, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                Path { path in
                    path.move(to: CGPoint(x: center + 2, y: 0))
                    path.addLine(to: CGPoint(x: center + 2, y: splitY))
                    path.addLine(to: CGPoint(x: proxy.size.width * 0.76, y: splitY))
                    path.addLine(to: CGPoint(x: proxy.size.width * 0.76, y: proxy.size.height))
                }
                .stroke(AppTheme.red, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private struct QatarClosingBalanceEditor: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @Binding private var storedAccountIDs: String
    @State private var selectedIDs: Set<UUID>

    init(storedAccountIDs: Binding<String>) {
        _storedAccountIDs = storedAccountIDs
        _selectedIDs = State(initialValue: Set(ClosingBalanceAccountStorage.decode(storedAccountIDs.wrappedValue)))
    }

    private var qatarAccounts: [LedgerAccount] {
        store.activeAccounts.filter { $0.group == .qatar }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Button("Select All") { selectedIDs = Set(qatarAccounts.map(\.id)) }
                    Spacer()
                    Button("Deselect All") { selectedIDs.removeAll() }
                }
                ForEach(qatarAccounts) { account in
                    Button { toggle(account.id) } label: {
                        HStack(spacing: 12) {
                            Label(account.name, systemImage: account.icon)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("QAR")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Image(systemName: selectedIDs.contains(account.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedIDs.contains(account.id) ? AppTheme.purple : .secondary)
                        }
                    }
                }
            } header: {
                Text("Qatar Accounts (\(selectedIDs.count) Selected)")
            } footer: {
                Text("The card uses the report’s starting date and totals these accounts immediately before that period begins. It is included in Net Balance and does not modify any transaction.")
            }
        }
        .navigationTitle("Opening Balance Card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let valid = Set(qatarAccounts.map(\.id))
                    storedAccountIDs = ClosingBalanceAccountStorage.encode(
                        Array(selectedIDs.intersection(valid)).sorted { $0.uuidString < $1.uuidString }
                    )
                    dismiss()
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }
}

private struct FinanceSummaryCardEditor: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("FinanceSummaryCustomCardsV1") private var storedCards = "[]"
    @State private var card: FinanceSummaryCustomCard
    let reportPeriodEnd: Date

    init(card: FinanceSummaryCustomCard, reportPeriodEnd: Date) {
        _card = State(initialValue: card)
        self.reportPeriodEnd = reportPeriodEnd
    }

    private var currencies: [String] {
        Array(Set(store.activeAccounts.map { $0.currencyCode.uppercased() })).sorted()
    }

    private var availableAccounts: [LedgerAccount] {
        store.activeAccounts.filter {
            $0.currencyCode.caseInsensitiveCompare(card.currencyCode) == .orderedSame
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selectedIDs: Set<UUID> {
        Set(card.accountIDs)
    }

    private var balanceMode: FinanceSummaryBalanceMode {
        FinanceSummaryBalanceMode(rawValue: card.balanceMode ?? "") ?? .current
    }

    private var previewCutoff: Date? {
        switch balanceMode {
        case .current:
            return nil
        case .closingDate:
            let date = card.balanceDate ?? Date()
            return Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date))
        case .reportPeriodEnd:
            return reportPeriodEnd
        }
    }

    private var previewBalance: Decimal {
        store.combinedBalance(
            for: availableAccounts.filter { selectedIDs.contains($0.id) },
            before: previewCutoff
        )
    }

    var body: some View {
        Form {
            Section("Card") {
                TextField("Card title", text: $card.title)
                    .textInputAutocapitalization(.words)
                Picker("Currency", selection: $card.currencyCode) {
                    ForEach(currencies, id: \.self) { currency in
                        Text(currency).tag(currency)
                    }
                }
                .onChange(of: card.currencyCode) { _ in
                    let validIDs = Set(availableAccounts.map(\.id))
                    card.accountIDs.removeAll { !validIDs.contains($0) }
                }
            }

            Section {
                HStack {
                    Button("Select All") {
                        card.accountIDs = availableAccounts.map(\.id)
                    }
                    Spacer()
                    Button("Deselect All") {
                        card.accountIDs.removeAll()
                    }
                }

                ForEach(availableAccounts) { account in
                    Button {
                        toggle(account.id)
                    } label: {
                        HStack {
                            Label(account.name, systemImage: account.icon)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(DisplayFormat.currency(store.balance(for: account), code: account.currencyCode))
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Image(systemName: selectedIDs.contains(account.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedIDs.contains(account.id) ? AppTheme.purple : .secondary)
                        }
                    }
                }
            } header: {
                Text("Accounts (\(card.accountIDs.count) Selected)")
            } footer: {
                Text("Only accounts using the selected currency can be combined on one card.")
            }


            Section {
                Picker("Balance At", selection: Binding(
                    get: { balanceMode },
                    set: { mode in
                        card.balanceMode = mode.rawValue
                        if mode == .closingDate, card.balanceDate == nil {
                            card.balanceDate = Date()
                        }
                    }
                )) {
                    ForEach(FinanceSummaryBalanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if balanceMode == .closingDate {
                    DatePicker(
                        "Closing Date",
                        selection: Binding(
                            get: { card.balanceDate ?? Date() },
                            set: { card.balanceDate = $0 }
                        ),
                        in: ...Date(),
                        displayedComponents: .date
                    )
                } else if balanceMode == .reportPeriodEnd {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Follows the selected Financial Summary period", systemImage: "calendar.badge.clock")
                        Text("Closing: \((Calendar.current.date(byAdding: .day, value: -1, to: reportPeriodEnd) ?? reportPeriodEnd).formatted(date: .abbreviated, time: .omitted))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Balance Date or Period")
            } footer: {
                Text("Closing Date includes every transaction recorded through the end of that day.")
            }

            Section("Preview") {
                LabeledContent(
                    card.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Selected Account Balance"
                        : card.title,
                    value: DisplayFormat.currency(previewBalance, code: card.currencyCode)
                )
            }
        }
        .navigationTitle("Account Balance Card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
                .disabled(card.accountIDs.isEmpty)
            }
        }
        .onAppear {
            if card.balanceMode == nil {
                card.balanceMode = FinanceSummaryBalanceMode.current.rawValue
            }
            if !currencies.contains(card.currencyCode.uppercased()), let first = currencies.first {
                card.currencyCode = first
            }
        }
    }

    private func toggle(_ id: UUID) {
        if let index = card.accountIDs.firstIndex(of: id) {
            card.accountIDs.remove(at: index)
        } else {
            card.accountIDs.append(id)
        }
    }

    private func save() {
        var cards = FinanceSummaryCardStorage.decode(storedCards)
        card.title = card.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = cards.firstIndex(where: { $0.id == card.id }) {
            cards[index] = card
        } else {
            cards.append(card)
        }
        storedCards = FinanceSummaryCardStorage.encode(cards)
    }
}

private struct ChartLegend: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct ComparisonTransactionsView: View {
    @EnvironmentObject private var store: LedgerStore
    let interval: DateInterval
    var body: some View {
        List {
            Section("Income") { rows(for: .income) }
            Section("Expenses") { rows(for: .expense) }
        }
        .navigationTitle("Compared Transactions")
        .navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private func rows(for type: TransactionType) -> some View {
        let items = transactions.filter { type == .income ? store.isReportIncome($0) : $0.type == type }
        if items.isEmpty {
            Text("No \(type.title.lowercased()) transactions.").foregroundStyle(.secondary)
        } else {
            ForEach(items) {
                TransactionRow(
                    transaction: $0,
                    accountID: type == .income ? store.reportIncomeAccountID($0) : nil
                )
            }
            LabeledContent("Total", value: DisplayFormat.currency(items.reduce(0) {
                $0 + (type == .income ? store.reportIncomeAmount($1) : $1.amount)
            }, code: store.currencyCode))
        }
    }
    private var transactions: [LedgerTransaction] {
        store.transactions.filter {
            guard interval.contains($0.date) else { return false }
            if store.isReportIncome($0) {
                return store.account(withID: store.reportIncomeAccountID($0))?.currencyCode == store.currencyCode
            }
            return $0.type == .expense &&
                store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
        }.sorted { $0.date > $1.date }
    }
}

private struct AccountReportTransactionsView: View {
    @EnvironmentObject private var store: LedgerStore
    let interval: DateInterval
    let accountIDs: Set<UUID>
    let type: TransactionType
    @State private var selectedTransaction: LedgerTransaction?

    var body: some View {
        List {
            ForEach(transactions) { transaction in
                Button { selectedTransaction = transaction } label: {
                    TransactionRow(
                        transaction: transaction,
                        accountID: type == .income ? store.reportIncomeAccountID(transaction) : nil
                    )
                }.buttonStyle(.plain)
            }
            Section {
                LabeledContent("\(type.title) Total", value: formatted(total))
                LabeledContent("Transactions", value: "\(transactions.count)")
            }
        }
        .navigationTitle("Account Transactions")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedTransaction) {
            TransactionSnapshotView(transaction: $0).environmentObject(store)
        }
    }
    private var transactions: [LedgerTransaction] {
        store.transactions.filter {
            guard interval.contains($0.date) else { return false }
            if type == .income {
                return store.isReportIncome($0) &&
                    accountIDs.contains(store.reportIncomeAccountID($0) ?? LedgerAccount.legacyMainID)
            }
            return accountIDs.contains($0.accountID ?? LedgerAccount.legacyMainID) && $0.type == type
        }.sorted { $0.date > $1.date }
    }
    private var total: Decimal {
        transactions.reduce(0) {
            $0 + (type == .income ? store.reportIncomeAmount($1) : $1.amount)
        }
    }
    private func formatted(_ amount: Decimal) -> String {
        DisplayFormat.currency(amount, code: store.currencyCode)
    }
}

private enum LoanMovementKind {
    case increased, paid
}

private struct LoanTransactionsView: View {
    @EnvironmentObject private var store: LedgerStore
    let interval: DateInterval
    let currency: String
    let movement: LoanMovementKind
    @State private var selectedTransaction: LedgerTransaction?

    var body: some View {
        List {
            ForEach(transactions) { transaction in
                Button { selectedTransaction = transaction } label: {
                    TransactionRow(transaction: transaction)
                }.buttonStyle(.plain)
            }
            LabeledContent("Total", value: DisplayFormat.currency(total, code: currency))
        }
        .navigationTitle(movement == .increased ? "Loan Increased" : "Loan Decreased / Paid")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedTransaction) {
            TransactionSnapshotView(transaction: $0).environmentObject(store)
        }
    }
    private var loanIDs: Set<UUID> {
        Set(store.accounts.filter {
            ($0.group == .payments || $0.nature == .loan) && $0.currencyCode == currency
        }.map(\.id))
    }
    private var transactions: [LedgerTransaction] {
        store.transactions.filter {
            guard interval.contains($0.date) else { return false }
            switch movement {
            case .increased:
                return ($0.type == .expense || $0.type == .transfer) &&
                    loanIDs.contains($0.accountID ?? LedgerAccount.legacyMainID)
            case .paid:
                return $0.type == .transfer && loanIDs.contains($0.destinationAccountID ?? LedgerAccount.legacyMainID)
            }
        }.sorted { $0.date > $1.date }
    }
    private var total: Decimal {
        transactions.reduce(0) {
            $0 + (movement == .paid ? ($1.destinationAmount ?? $1.amount) : $1.amount)
        }
    }
}

private struct AccountNatureReportView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var start = Calendar.current.dateInterval(of: .month, for: Date())!.start
    @State private var end = Date()

    var body: some View {
        List {
            Section("Custom Dates") {
                DatePicker("From", selection: $start, displayedComponents: .date)
                DatePicker("To", selection: $end, in: start..., displayedComponents: .date)
            }
            ForEach(natures, id: \.self) { nature in
                Section(nature.title) {
                    NavigationLink {
                        NatureTransactionsView(nature: nature, interval: interval, type: .income)
                    } label: {
                        metric("Income", type: .income, nature: nature)
                    }
                    NavigationLink {
                        NatureTransactionsView(nature: nature, interval: interval, type: .expense)
                    } label: {
                        metric("Recorded Expenses", type: .expense, nature: nature)
                    }
                    ForEach(currencyBalances(nature)) { item in
                        LabeledContent("\(item.currency) account balance",
                                       value: DisplayFormat.currency(item.amount, code: item.currency))
                    }
                }
            }
        }
        .navigationTitle("Account Nature Report")
        .navigationBarTitleDisplayMode(.inline)
    }
    private var interval: DateInterval {
        DateInterval(start: Calendar.current.startOfDay(for: start),
            end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end))!)
    }
    private var natures: [AccountNature] {
        let values = Set(store.accounts.map(effectiveNature))
        return AccountNature.allCases.filter { $0 != .unassigned && values.contains($0) }
    }
    private func effectiveNature(_ account: LedgerAccount) -> AccountNature {
        if account.group == .payments { return .loan }
        if account.group == .assets { return .asset }
        return account.nature ?? .unassigned
    }
    private func accounts(_ nature: AccountNature) -> [LedgerAccount] {
        store.accounts.filter { effectiveNature($0) == nature }
    }
    private func metric(_ title: String, type: TransactionType, nature: AccountNature) -> some View {
        let ids = Set(accounts(nature).map(\.id))
        let items = store.transactions.filter {
            guard interval.contains($0.date) else { return false }
            if type == .income {
                return store.isReportIncome($0) &&
                    ids.contains(store.reportIncomeAccountID($0) ?? LedgerAccount.legacyMainID)
            }
            return $0.type == type && ids.contains($0.accountID ?? LedgerAccount.legacyMainID)
        }
        return HStack {
            VStack(alignment: .leading) {
                Text(title)
                Text("\(items.count) transactions").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(currencySummary(items)).font(.caption.bold())
        }
    }
    private func currencySummary(_ items: [LedgerTransaction]) -> String {
        Dictionary(grouping: items) {
            let id = store.isReportIncome($0) ? store.reportIncomeAccountID($0) : $0.accountID
            return store.account(withID: id)?.currencyCode ?? store.currencyCode
        }
            .map { code, values in
                DisplayFormat.currency(values.reduce(0) {
                    $0 + (store.isReportIncome($1) ? store.reportIncomeAmount($1) : $1.amount)
                }, code: code)
            }.sorted().joined(separator: " · ")
    }
    private func currencyBalances(_ nature: AccountNature) -> [NatureCurrencyBalance] {
        Dictionary(grouping: accounts(nature), by: \.currencyCode).map { code, accounts in
            NatureCurrencyBalance(currency: code, amount: accounts.reduce(0) { $0 + store.balance(for: $1) })
        }.sorted { $0.currency < $1.currency }
    }
}

private struct NatureTransactionsView: View {
    @EnvironmentObject private var store: LedgerStore
    let nature: AccountNature
    let interval: DateInterval
    let type: TransactionType
    @State private var selectedTransaction: LedgerTransaction?
    var body: some View {
        List {
            ForEach(transactions) { item in
                Button { selectedTransaction = item } label: {
                    TransactionRow(
                        transaction: item,
                        accountID: type == .income ? store.reportIncomeAccountID(item) : nil
                    )
                }
                    .buttonStyle(.plain)
            }
        }
        .navigationTitle("\(nature.title) \(type.title)")
        .sheet(item: $selectedTransaction) {
            TransactionSnapshotView(transaction: $0).environmentObject(store)
        }
    }
    private var accountIDs: Set<UUID> {
        Set(store.accounts.filter {
            if $0.group == .payments { return nature == .loan }
            if $0.group == .assets { return nature == .asset }
            return $0.nature == nature
        }.map(\.id))
    }
    private var transactions: [LedgerTransaction] {
        store.transactions.filter {
            guard interval.contains($0.date) else { return false }
            if type == .income {
                return store.isReportIncome($0) &&
                    accountIDs.contains(store.reportIncomeAccountID($0) ?? LedgerAccount.legacyMainID)
            }
            return $0.type == type && accountIDs.contains($0.accountID ?? LedgerAccount.legacyMainID)
        }.sorted { $0.date > $1.date }
    }
}

private struct BalanceReconciliationReportView: View {
    @EnvironmentObject private var store: LedgerStore
    var body: some View {
        List {
            ForEach(store.activeAccounts) { account in
                Section(account.name) {
                    LabeledContent("Books balance",
                                   value: DisplayFormat.currency(store.balance(for: account), code: account.currencyCode))
                    if let reported = latestReportedBalance(account) {
                        LabeledContent(reported.label,
                                       value: DisplayFormat.currency(reported.amount, code: reported.currency))
                        LabeledContent("Difference",
                                       value: DisplayFormat.currency(reported.amount - store.balance(for: account), code: reported.currency))
                        Label(
                            reported.amount == store.balance(for: account) ? "Matched" : "Difference found",
                            systemImage: reported.amount == store.balance(for: account)
                                ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(reported.amount == store.balance(for: account) ? AppTheme.green : AppTheme.orange)
                        Text("From \(reported.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("No balance or available-limit value was found in this account’s imported messages.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Balance Reconciliation")
        .navigationBarTitleDisplayMode(.inline)
    }
    private func latestReportedBalance(_ account: LedgerAccount) -> (label: String, amount: Decimal, currency: String, date: Date)? {
        let candidates = store.transactions.filter { $0.accountID == account.id && !$0.details.isEmpty }
            .sorted { $0.date > $1.date }
        let patterns = [
            ("Card Available Balance", #"(?i)Card\s+Available\s+Balance:\s*([A-Z]{3})\s*([\d,]+(?:\.\d{1,2})?)"#),
            ("Available Limit", #"(?i)Available\s+Limit:\s*([A-Z]{3})\s*([\d,]+(?:\.\d{1,2})?)"#),
            ("Message Balance", #"(?i)(?:Current\s+)?Balance:\s*([A-Z]{3})\s*([\d,]+(?:\.\d{1,2})?)"#)
        ]
        for transaction in candidates {
            for (label, pattern) in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: transaction.details, range: NSRange(transaction.details.startIndex..., in: transaction.details)),
                      let currencyRange = Range(match.range(at: 1), in: transaction.details),
                      let amountRange = Range(match.range(at: 2), in: transaction.details),
                      let amount = Decimal(string: String(transaction.details[amountRange]).replacingOccurrences(of: ",", with: ""))
                else { continue }
                return (label, amount, String(transaction.details[currencyRange]), transaction.date)
            }
        }
        return nil
    }
}
