import SwiftUI

private enum DashboardDatePreset: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "This Week"
    case month = "This Month"
    case year = "This Year"
    case custom = "Custom"
    var id: String { rawValue }
}

struct DashboardView: View {
    @EnvironmentObject private var store: LedgerStore
    let onAdd: (TransactionType) -> Void
    let onTransfer: () -> Void
    @AppStorage("DashboardDatePreset") private var storedDatePreset = DashboardDatePreset.month.rawValue
    @AppStorage("DashboardCustomStart") private var storedCustomStart = Date().timeIntervalSince1970
    @AppStorage("DashboardCustomEnd") private var storedCustomEnd = Date().timeIntervalSince1970
    @State private var showingCustomDates = false
    @State private var draftStartDate = Date()
    @State private var draftEndDate = Date()
    @State private var transactionSearch = ""
    @AppStorage("DashboardAccountSelection") private var selectedAccountValue = "all"

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header
                    dateFilter
                    accountFilter
                    BalanceCard(
                        balance: filteredTotals.balance,
                        income: filteredTotals.income,
                        expense: filteredTotals.expense,
                        loan: filteredTotals.loan,
                        currencyCode: store.currencyCode
                    )
                    quickActions
                    recentTransactions
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .background(AppTheme.page)
            .navigationBarHidden(true)
            .sheet(isPresented: $showingCustomDates) {
                NavigationStack {
                    Form {
                        DatePicker("From", selection: $draftStartDate, displayedComponents: .date)
                        DatePicker("To", selection: $draftEndDate, displayedComponents: .date)
                    }
                    .navigationTitle("Custom Dashboard Period")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingCustomDates = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                storedCustomStart = draftStartDate.timeIntervalSince1970
                                storedCustomEnd = draftEndDate.timeIntervalSince1970
                                storedDatePreset = DashboardDatePreset.custom.rawValue
                                showingCustomDates = false
                            }
                        }
                    }
                }
            }
        }
    }

    private var dateFilter: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Dashboard period").font(.headline)
                Spacer()
                Text(periodTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.purple)
            }
            Menu {
                ForEach(DashboardDatePreset.allCases) { preset in
                    Button {
                        if preset == .custom {
                            draftStartDate = Date(timeIntervalSince1970: storedCustomStart)
                            draftEndDate = Date(timeIntervalSince1970: storedCustomEnd)
                            showingCustomDates = true
                        } else {
                            storedDatePreset = preset.rawValue
                        }
                    } label: {
                        if selectedDatePreset == preset {
                            Label(preset.rawValue, systemImage: "checkmark")
                        } else {
                            Text(preset.rawValue)
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "calendar")
                    Text(selectedDatePreset.rawValue)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                }
                .font(.subheadline.weight(.semibold))
                .padding(13)
                .background(.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
        }
    }

    private var accountFilter: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Dashboard account").font(.headline)
            Picker("Dashboard account", selection: $selectedAccountValue) {
                Text("All \(store.currencyCode) Accounts").tag("all")
                ForEach(store.activeAccounts.filter { $0.currencyCode == store.currencyCode }) { account in
                    Text(account.name).tag(account.id.uuidString)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Daily Ledger")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                Text("Your money at a glance")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(AppTheme.balanceGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.top, 16)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick add")
                .font(.headline)
            HStack(spacing: 12) {
                QuickActionButton(
                    title: "Income",
                    subtitle: "Money received",
                    icon: "plus",
                    colors: [AppTheme.green, AppTheme.teal]
                ) { onAdd(.income) }

                QuickActionButton(
                    title: "Expense",
                    subtitle: "Money spent",
                    icon: "minus",
                    colors: [AppTheme.orange, AppTheme.red]
                ) { onAdd(.expense) }
            }
            QuickActionButton(
                title: "Transfer",
                subtitle: "Move money between accounts",
                icon: "arrow.left.arrow.right",
                colors: [AppTheme.purple, AppTheme.blue]
            ) { onTransfer() }
        }
    }

    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent transactions")
                    .font(.headline)
                Spacer()
                Text("\(periodTitle): \(filteredTotals.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search recent transactions", text: $transactionSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !transactionSearch.isEmpty {
                    Button {
                        transactionSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if filteredTransactions.isEmpty {
                EmptyLedgerView(
                    title: "No transactions yet",
                    message: "Use one of the colorful buttons above to add your first entry."
                )
                .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredTransactions.prefix(6).enumerated()), id: \.element.id) { index, transaction in
                        TransactionRow(transaction: transaction)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                        if index < min(filteredTransactions.count, 6) - 1 {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .padding(.vertical, 6)
                .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    private var selectedDatePreset: DashboardDatePreset {
        DashboardDatePreset(rawValue: storedDatePreset) ?? .month
    }

    private var selectedInterval: DateInterval {
        let calendar = Calendar.current
        switch selectedDatePreset {
        case .today:
            return calendar.dateInterval(of: .day, for: Date())!
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: Date())!
        case .month:
            return calendar.dateInterval(of: .month, for: Date())!
        case .year:
            return calendar.dateInterval(of: .year, for: Date())!
        case .custom:
            let first = Date(timeIntervalSince1970: storedCustomStart)
            let second = Date(timeIntervalSince1970: storedCustomEnd)
            let start = calendar.startOfDay(for: min(first, second))
            let endDay = calendar.startOfDay(for: max(first, second))
            let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
            return DateInterval(start: start, end: end)
        }
    }

    private var filteredTotals: LedgerTotals {
        store.totals(in: selectedInterval, accountID: selectedAccountID)
    }

    private var filteredTransactions: [LedgerTransaction] {
        store.transactions.filter {
            let accountMatches = selectedAccountID == nil ||
                $0.accountID == selectedAccountID || $0.destinationAccountID == selectedAccountID
            guard selectedInterval.contains($0.date), accountMatches, !transactionSearch.isEmpty else {
                return selectedInterval.contains($0.date) && accountMatches
            }
            return $0.category.localizedCaseInsensitiveContains(transactionSearch) ||
                ($0.vendor?.localizedCaseInsensitiveContains(transactionSearch) ?? false) ||
                $0.details.localizedCaseInsensitiveContains(transactionSearch) ||
                NSDecimalNumber(decimal: $0.amount).stringValue.contains(transactionSearch)
        }
    }

    private var selectedAccountID: UUID? {
        selectedAccountValue == "all" ? nil : UUID(uuidString: selectedAccountValue)
    }

    private var periodTitle: String {
        switch selectedDatePreset {
        case .today: return "Today"
        case .week: return "This week"
        case .month: return "This month"
        case .year: return "This year"
        case .custom:
            return "\(DisplayFormat.day.string(from: selectedInterval.start)) – \(DisplayFormat.day.string(from: selectedInterval.end.addingTimeInterval(-1)))"
        }
    }

}

private struct QuickActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let colors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.20), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}
