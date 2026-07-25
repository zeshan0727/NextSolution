import SwiftUI

struct BudgetSettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var editorBudget: ExpenseBudget?
    @State private var showingNewBudget = false

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
                            editorBudget = budget
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
                    Text("This Month")
                } footer: {
                    Text("Only expense transactions in the matching category and currency count toward each budget.")
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
                    showingNewBudget = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add budget")
            }
        }
        .sheet(isPresented: $showingNewBudget) {
            NavigationStack {
                BudgetEditorView(
                    budget: ExpenseBudget(
                        category: "",
                        monthlyAmount: 0,
                        currencyCode: store.currencyCode
                    )
                )
            }
        }
        .sheet(item: $editorBudget) { budget in
            NavigationStack {
                BudgetEditorView(budget: budget)
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
                                    Text(budget.category)
                                        .font(.headline)
                                    Text(budget.currencyCode)
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
                Label(budget.category, systemImage: AppTheme.categoryIcon(budget.category))
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
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var budget: ExpenseBudget
    @State private var amountText: String
    @State private var categorySearch = ""

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
                TextField("Category", text: $budget.category)
                    .textInputAutocapitalization(.words)
                TextField("Monthly amount", text: $amountText)
                    .keyboardType(.decimalPad)
                Picker("Currency", selection: $budget.currencyCode) {
                    ForEach(["QAR", "PKR", "USD", "EUR", "GBP", "AED", "SAR", "INR"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                Toggle("Alert when 80% is reached", isOn: $budget.alertsEnabled)
            }

            Section("Choose Existing Category") {
                TextField("Search categories", text: $categorySearch)
                ForEach(categories, id: \.self) { category in
                    Button(category) {
                        budget.category = category
                    }
                }
            }
        }
        .navigationTitle(budget.monthlyAmount > 0 ? "Edit Budget" : "New Budget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let amount = Decimal(string: amountText), amount > 0 else { return }
                    budget.monthlyAmount = amount
                    store.saveBudget(budget)
                    dismiss()
                }
                .disabled(
                    budget.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    Decimal(string: amountText).map { $0 <= 0 } != false
                )
            }
        }
    }
}
