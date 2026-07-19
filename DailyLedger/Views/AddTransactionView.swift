import SwiftUI

struct AddTransactionView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var type: TransactionType
    @State private var amountText = ""
    @State private var date = Date()
    @State private var category: String
    @State private var details = ""
    @FocusState private var amountFocused: Bool
    private let editingTransaction: LedgerTransaction?

    init(initialType: TransactionType) {
        editingTransaction = nil
        _type = State(initialValue: initialType)
        _category = State(initialValue: initialType == .expense ? "Food" : "Salary")
    }

    init(transaction: LedgerTransaction) {
        editingTransaction = transaction
        _type = State(initialValue: transaction.type)
        _amountText = State(initialValue: NSDecimalNumber(decimal: transaction.amount).stringValue)
        _date = State(initialValue: transaction.date)
        _category = State(initialValue: transaction.category)
        _details = State(initialValue: transaction.details)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    typePicker
                    amountEditor
                    categoryPicker
                    detailsEditor
                    dateEditor
                }
                .padding(18)
                .padding(.bottom, 82)
            }
            .background(AppTheme.page)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                saveButton
            }
            .onAppear { amountFocused = true }
            .onChange(of: type) { newType in
                let available = categories(for: newType)
                if !available.contains(category) {
                    category = newType == .expense ? "Food" : "Salary"
                }
            }
        }
        .presentationDetents([.large])
    }

    private var typePicker: some View {
        Picker("Transaction type", selection: $type) {
            Text("Expense").tag(TransactionType.expense)
            Text("Income").tag(TransactionType.income)
        }
        .pickerStyle(.segmented)
    }

    private var amountEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Amount")
                .font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(store.currencyCode)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .focused($amountFocused)
                    .accessibilityLabel("Transaction amount")
            }
            .padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                ForEach(categories(for: type), id: \.self) { item in
                    Button {
                        category = item
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: AppTheme.categoryIcon(item))
                                .font(.system(size: 17, weight: .semibold))
                            Text(item)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(category == item ? .white : AppTheme.categoryColor(item))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            category == item
                                ? AppTheme.categoryColor(item)
                                : AppTheme.categoryColor(item).opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(category == item ? .isSelected : [])
                }
            }
        }
    }

    private var detailsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Description")
                .font(.headline)
            TextField("Example: Lunch, petrol, client payment", text: $details)
                .textInputAutocapitalization(.sentences)
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var dateEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Date")
                .font(.headline)
            DatePicker("Transaction date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Label(
                editingTransaction == nil
                    ? (type == .income ? "Save Income" : "Save Expense")
                    : "Update Transaction",
                systemImage: editingTransaction == nil
                    ? (type == .income ? "plus.circle.fill" : "minus.circle.fill")
                    : "checkmark.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(buttonGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .disabled(parsedAmount == nil)
        .opacity(parsedAmount == nil ? 0.5 : 1)
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var buttonGradient: LinearGradient {
        LinearGradient(
            colors: type == .income
                ? [AppTheme.green, AppTheme.teal]
                : [AppTheme.orange, AppTheme.red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var navigationTitle: String {
        if editingTransaction != nil { return "Edit Transaction" }
        return type == .income ? "Add Income" : "Add Expense"
    }

    private var parsedAmount: Decimal? {
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        guard let amount = Decimal(
            string: normalized,
            locale: Locale(identifier: "en_US_POSIX")
        ), amount > 0 else { return nil }
        return amount
    }

    private func categories(for type: TransactionType) -> [String] {
        type == .expense
            ? LedgerTransaction.expenseCategories
            : LedgerTransaction.incomeCategories
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        if var transaction = editingTransaction {
            transaction.type = type
            transaction.amount = amount
            transaction.date = date
            transaction.category = category
            transaction.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
            store.update(transaction)
        } else {
            store.add(
                type: type,
                amount: amount,
                date: date,
                category: category,
                details: details
            )
        }
        dismiss()
    }
}
