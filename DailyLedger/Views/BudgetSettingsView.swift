import SwiftUI

private struct BudgetEditorRoute: Identifiable {
    let id = UUID()
    let budget: ExpenseBudget
}

struct BudgetSettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var editorRoute: BudgetEditorRoute?

    private var budgets: [ExpenseBudget] {
        store.settings.expenseBudgets
    }

    var body: some View {
        List {
            if budgets.isEmpty {
                Section {
                    EmptyBudgetMessage(
                        title: "No Budgets Yet",
                        detail: "Create a monthly category budget to track spending and receive an alert at 80%.",
                        icon: "target"
                    )
                }
            } else {
                Section {
                    ForEach(budgets) { budget in
                        Button {
                            editorRoute = BudgetEditorRoute(budget: budget)
                        } label: {
                            BudgetProgressRow(
                                budget: budget,
                                spent: store.monthlyBudgetSpent(budget)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: store.deleteBudgets)
                } header: {
                    Text("Current Budget Cycle")
                } footer: {
                    Text("Only expenses in the selected types, currency and custom date cycle count toward each budget.")
                }
            }

            Section {
                NavigationLink {
                    BudgetPlannerView()
                } label: {
                    Label("Open Budget Planner", systemImage: "wand.and.stars")
                }
            } footer: {
                Text("The planner recommends amounts only for the categories you create here.")
            }
        }
        .navigationTitle("Budgets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    editorRoute = BudgetEditorRoute(
                        budget: ExpenseBudget(
                            categories: [],
                            monthlyAmount: 0,
                            currencyCode: store.currencyCode
                        )
                    )
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add budget")
            }
        }
        .fullScreenCover(item: $editorRoute) { route in
            NavigationStack {
                BudgetEditorView(budget: route.budget)
            }
        }
    }
}

struct BudgetPlannerView: View {
    @EnvironmentObject private var store: LedgerStore
    @AppStorage("MonthlyIncomePrimary") private var primaryIncome = 0.0
    @AppStorage("MonthlyIncomeSecondary") private var secondaryIncome = 0.0

    private var budgets: [ExpenseBudget] {
        store.settings.expenseBudgets
    }

    var body: some View {
        List {
            Section("Monthly Income") {
                Stepper(
                    "Primary: \(DisplayFormat.currency(Decimal(primaryIncome), code: store.currencyCode))",
                    value: $primaryIncome,
                    in: 0...1_000_000,
                    step: 500
                )
                Stepper(
                    "Other fixed: \(DisplayFormat.currency(Decimal(secondaryIncome), code: store.currencyCode))",
                    value: $secondaryIncome,
                    in: 0...1_000_000,
                    step: 500
                )
            }

            if budgets.isEmpty {
                Section {
                    EmptyBudgetMessage(
                        title: "Create a Budget First",
                        detail: "Add categories in Settings → Budgets, then return for tailored suggestions.",
                        icon: "list.bullet.clipboard"
                    )
                }
            } else {
                Section {
                    ForEach(budgets) { budget in
                        let suggestion = suggestedAmount(for: budget)
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(budget.displayName)
                                        .font(.headline)
                                    Text("\(budget.categories.count) expense type\(budget.categories.count == 1 ? "" : "s") · \(budget.currencyCode)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(DisplayFormat.currency(suggestion, code: budget.currencyCode))
                                        .font(.headline)
                                    Text("Suggested monthly")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Button("Use This Suggestion") {
                                var updated = budget
                                updated.monthlyAmount = suggestion
                                store.saveBudget(updated)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 5)
                    }
                } header: {
                    Text("Suggested Budgets")
                } footer: {
                    Text("Suggestions target about 10% below the average of the last three complete months. Categories without history share 80% of fixed income equally.")
                }
            }
        }
        .navigationTitle("Budget Planner")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func suggestedAmount(for budget: ExpenseBudget) -> Decimal {
        let income = budget.currencyCode == store.currencyCode
            ? Decimal(primaryIncome + secondaryIncome)
            : 0
        return store.suggestedBudgetAmount(for: budget, monthlyIncome: income)
    }
}

private struct EmptyBudgetMessage: View {
    let title: String
    let detail: String
    let icon: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(AppTheme.purple)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

private struct BudgetProgressRow: View {
    let budget: ExpenseBudget
    let spent: Decimal

    private var progress: Double {
        guard budget.monthlyAmount > 0 else { return 0 }
        return min(
            NSDecimalNumber(decimal: spent / budget.monthlyAmount).doubleValue,
            1
        )
    }

    private var color: Color {
        if spent >= budget.monthlyAmount { return AppTheme.red }
        if progress >= 0.8 { return AppTheme.orange }
        return AppTheme.green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(
                    budget.displayName,
                    systemImage: AppTheme.categoryIcon(budget.categories.first ?? "Other")
                )
                    .font(.headline)
                Spacer()
                if budget.alertsEnabled {
                    Image(systemName: "bell.fill")
                        .font(.caption)
                        .foregroundStyle(progress >= 0.8 ? AppTheme.orange : .secondary)
                }
            }
            ProgressView(value: progress)
                .tint(color)
            Text(budget.categories.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text("Cycle: day \(budget.cycleStartDay) to day \(budget.cycleEndDay)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Text("\(DisplayFormat.currency(spent, code: budget.currencyCode)) spent")
                Spacer()
                Text("\(DisplayFormat.currency(budget.monthlyAmount, code: budget.currencyCode)) budget")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}

private struct BudgetEditorView: View {
    private enum FocusedField: Hashable {
        case name
        case amount
        case search
    }

    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var budget: ExpenseBudget
    @State private var amountText: String
    @State private var categorySearch = ""
    @FocusState private var focusedField: FocusedField?

    init(budget: ExpenseBudget) {
        _budget = State(initialValue: budget)
        _amountText = State(
            initialValue: budget.monthlyAmount > 0
                ? NSDecimalNumber(decimal: budget.monthlyAmount).stringValue
                : ""
        )
    }

    private var categories: [String] {
        let all = store.categories(for: .expense).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        guard !categorySearch.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(categorySearch) }
    }

    var body: some View {
        Form {
            Section("Budget") {
                TextField("Budget name (optional)", text: $budget.name)
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: .name)
                TextField("Monthly amount", text: $amountText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .amount)
                Picker("Currency", selection: $budget.currencyCode) {
                    ForEach(["QAR", "PKR", "USD", "EUR", "GBP", "AED", "SAR", "INR"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                Toggle("Alert when 80% is reached", isOn: $budget.alertsEnabled)
            }

            Section {
                Picker("Cycle starts on", selection: $budget.cycleStartDay) {
                    ForEach(1...28, id: \.self) { day in
                        Text("Day \(day)").tag(day)
                    }
                }
                Picker("Cycle ends on", selection: $budget.cycleEndDay) {
                    ForEach(1...28, id: \.self) { day in
                        Text("Day \(day)").tag(day)
                    }
                }
            } header: {
                Text("Budget Dates")
            } footer: {
                Text("For example, choose start day 26 and end day 25 for a salary-month budget.")
            }

            Section {
                TextField("Search categories", text: $categorySearch)
                    .focused($focusedField, equals: .search)
                if !budget.categories.isEmpty {
                    Button("Clear Selection") {
                        focusedField = nil
                        budget.categories.removeAll()
                    }
                }
                ForEach(categories, id: \.self) { category in
                    Button {
                        focusedField = nil
                        toggleCategory(category)
                    } label: {
                        HStack {
                            Label(category, systemImage: AppTheme.categoryIcon(category))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(
                                systemName: budget.includes(category: category)
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            .foregroundStyle(
                                budget.includes(category: category)
                                    ? AppTheme.purple
                                    : .secondary
                            )
                        }
                    }
                }
            } header: {
                Text("Expense Types (\(budget.categories.count) Selected)")
            } footer: {
                Text("All selected expense types are combined into this one budget and one 80% warning.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(budget.monthlyAmount > 0 ? "Edit Budget" : "New Budget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    focusedField = nil
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let amount = Decimal(string: amountText), amount > 0 else { return }
                    focusedField = nil
                    budget.monthlyAmount = amount
                    store.saveBudget(budget)
                    dismiss()
                }
                .disabled(
                    budget.categories.isEmpty ||
                    Decimal(string: amountText).map { $0 <= 0 } != false
                )
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .onDisappear {
            focusedField = nil
        }
    }

    private func toggleCategory(_ category: String) {
        if let index = budget.categories.firstIndex(where: {
            $0.caseInsensitiveCompare(category) == .orderedSame
        }) {
            budget.categories.remove(at: index)
        } else {
            budget.categories.append(category)
            budget.categories.sort {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        }
    }
}
