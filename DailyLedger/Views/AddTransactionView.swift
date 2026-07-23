import SwiftUI

struct AddTransactionView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var type: TransactionType
    @State private var amountText = ""
    @State private var date = Date()
    @State private var category: String
    @State private var vendor = ""
    @State private var details = ""
    @State private var accountID: UUID?
    @State private var newCategory = ""
    @State private var categorySearch = ""
    @FocusState private var focusedField: Field?
    private let editingTransaction: LedgerTransaction?

    private enum Field: Hashable {
        case amount
        case newCategory
        case categorySearch
        case vendor
        case details
    }

    init(initialType: TransactionType, accountID: UUID? = nil) {
        editingTransaction = nil
        _type = State(initialValue: initialType)
        _category = State(initialValue: initialType == .expense ? "Food" : "Salary")
        _accountID = State(initialValue: accountID)
    }

    init(transaction: LedgerTransaction) {
        editingTransaction = transaction
        _type = State(initialValue: transaction.type)
        _amountText = State(initialValue: NSDecimalNumber(decimal: transaction.amount).stringValue)
        _date = State(initialValue: transaction.date)
        _category = State(initialValue: transaction.category)
        _vendor = State(initialValue: transaction.vendor ?? "")
        _details = State(initialValue: transaction.details)
        _accountID = State(initialValue: transaction.accountID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    typePicker
                    accountPicker
                    amountEditor
                    categoryPicker
                    detailsEditor
                    vendorEditor
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        focusedField = nil
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .accessibilityLabel("Hide keyboard")
                }
            }
            .safeAreaInset(edge: .bottom) {
                saveButton
            }
            .onAppear {
                if accountID == nil { accountID = store.defaultAccountID }
            }
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

    private var accountPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Account")
                .font(.headline)
            Picker("Account", selection: $accountID) {
                ForEach(store.activeAccounts) { account in
                    Text("\(account.name) · \(account.currencyCode)")
                        .tag(Optional(account.id))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var amountEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Amount")
                .font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(selectedAccount?.currencyCode ?? store.currencyCode)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .focused($focusedField, equals: .amount)
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
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search categories", text: $categorySearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .categorySearch)
                if !categorySearch.isEmpty {
                    Button {
                        categorySearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear category search")
                }
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                ForEach(visibleCategories, id: \.self) { item in
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
            HStack {
                TextField("Create a new category", text: $newCategory)
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: .newCategory)
                    .padding(12)
                    .background(.background, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Button("Add") {
                    let cleaned = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleaned.isEmpty else { return }
                    category = cleaned
                    newCategory = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var detailsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Description")
                .font(.headline)
            TextField("Example: Lunch, petrol, client payment", text: $details, axis: .vertical)
                .lineLimit(4...5)
                .frame(minHeight: 96, alignment: .topLeading)
                .textInputAutocapitalization(.sentences)
                .focused($focusedField, equals: .details)
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if !suggestedVendors.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text("Suggested:").font(.caption).foregroundStyle(.secondary)
                        ForEach(suggestedVendors, id: \.self) { suggestion in
                            Button(suggestion) { vendor = suggestion }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private var vendorEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Vendor")
                .font(.headline)
            TextField("Example: NEW NASCO RESTAURANT", text: $vendor)
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: .vendor)
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

    private var selectedAccount: LedgerAccount? {
        store.account(withID: accountID)
    }

    private func categories(for type: TransactionType) -> [String] {
        store.categories(for: type).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var filteredCategories: [String] {
        let items = categories(for: type)
        let query = categorySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var visibleCategories: [String] {
        let searched = filteredCategories
        if !categorySearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return searched }
        let usage = Dictionary(grouping: store.transactions.filter { $0.type == type }, by: \.category)
        let top = searched.sorted {
            let left = usage[$0]?.count ?? 0
            let right = usage[$1]?.count ?? 0
            return left == right
                ? $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                : left > right
        }
        var result = Array(top.prefix(3))
        if !result.contains(category) { result.append(category) }
        return result
    }

    private var suggestedVendors: [String] {
        if let extracted = extractedVendor { return [extracted] }
        let words = Set(details.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
        guard !words.isEmpty else { return [] }
        var scores: [String: Int] = [:]
        for transaction in store.transactions {
            guard let candidate = transaction.vendor, !candidate.isEmpty else { continue }
            let searchable = (transaction.details + " " + transaction.category).lowercased()
            let score = words.reduce(0) { $0 + (searchable.contains($1) ? 1 : 0) }
            if score > 0 { scores[candidate, default: 0] += score }
        }
        return scores.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(3).map(\.key)
    }

    private var extractedVendor: String? {
        let patterns = [
            #"(?i)\b(?:at|to|merchant)\s+([A-Z0-9][A-Z0-9 '&.-]{1,30}?)(?=\s+(?:on|at|for|using|card|amount)\b|[,.;]|$)"#,
            #"(?i)\b(?:from)\s+([A-Z0-9][A-Z0-9 '&.-]{1,30}?)(?=\s+(?:on|at|for|using|card|amount)\b|[,.;]|$)"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: details, range: NSRange(details.startIndex..., in: details)),
                  let range = Range(match.range(at: 1), in: details) else { continue }
            let value = details[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2 { return value }
        }
        return nil
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        if var transaction = editingTransaction {
            transaction.type = type
            transaction.amount = amount
            transaction.date = date
            transaction.category = category
            let cleanedVendor = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
            transaction.vendor = cleanedVendor.isEmpty ? nil : cleanedVendor
            transaction.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
            transaction.accountID = accountID ?? store.defaultAccountID
            transaction.destinationAccountID = nil
            transaction.destinationAmount = nil
            store.update(transaction)
        } else {
            store.add(
                type: type,
                amount: amount,
                date: date,
                category: category,
                vendor: vendor,
                details: details,
                accountID: accountID
            )
        }
        dismiss()
    }
}
