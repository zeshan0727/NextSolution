import SwiftUI

struct UncategorizedReviewView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var selectedCategory = "Food"
    @State private var skippedIDs: Set<UUID> = []

    var body: some View {
        Group {
            if let transaction = currentTransaction {
                Form {
                    Section("Transaction") {
                        LabeledContent("Amount") {
                            Text(DisplayFormat.currency(transaction.amount, code: currencyCode(for: transaction)))
                                .fontWeight(.semibold)
                        }
                        LabeledContent("Date", value: transaction.date.formatted(date: .abbreviated, time: .shortened))
                        if let vendor = transaction.vendor, !vendor.isEmpty {
                            LabeledContent("Vendor", value: vendor)
                        }
                        if !transaction.details.isEmpty {
                            Text(transaction.details)
                                .font(.subheadline)
                                .textSelection(.enabled)
                        }
                    }

                    Section("Choose category") {
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(categories, id: \.self) { category in
                                Label(category, systemImage: AppTheme.categoryIcon(category))
                                    .tag(category)
                            }
                        }
                        .pickerStyle(.navigationLink)

                        Button {
                            save(transaction)
                        } label: {
                            Label("Save Category", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Skip for Now") {
                            skippedIDs.insert(transaction.id)
                            prepareSelection()
                        }
                    }
                }
                .onAppear { prepareSelection() }
                .onChange(of: currentTransaction?.id) { _ in prepareSelection() }
            } else {
                EmptyLedgerView(
                    title: "Review Complete",
                    message: skippedIDs.isEmpty
                        ? "Every transaction now has a category."
                        : "You reviewed all remaining transactions for this session."
                )
                .padding()
            }
        }
        .navigationTitle("Review Uncategorized")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var currentTransaction: LedgerTransaction? {
        store.uncategorizedTransactions.first { !skippedIDs.contains($0.id) }
    }

    private var categories: [String] {
        store.categories(for: currentTransaction?.type ?? .expense).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private func prepareSelection() {
        guard let transaction = currentTransaction else { return }
        selectedCategory = store.suggestedCategory(for: transaction)
            ?? (transaction.type == .income ? "Salary" : "Food")
    }

    private func save(_ transaction: LedgerTransaction) {
        var updated = transaction
        updated.category = selectedCategory
        store.update(updated)
    }

    private func currencyCode(for transaction: LedgerTransaction) -> String {
        store.account(withID: transaction.accountID)?.currencyCode ?? store.currencyCode
    }
}
