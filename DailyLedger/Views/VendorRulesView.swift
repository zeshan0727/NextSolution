import SwiftUI

struct VendorRulesView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var editingRule: VendorCategoryRule?
    @State private var confirmingReset = false

    var body: some View {
        List {
            Section {
                if store.settings.vendorRules.isEmpty {
                    Text("No rules yet. Unmatched vendors are saved as Other.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.settings.vendorRules) { rule in
                        Button {
                            editingRule = rule
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: AppTheme.categoryIcon(rule.category))
                                    .foregroundStyle(AppTheme.categoryColor(rule.category))
                                    .frame(width: 34, height: 34)
                                    .background(
                                        AppTheme.categoryColor(rule.category).opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(rule.keyword)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(rule.category)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete(perform: store.deleteVendorRules)
                }
            } header: {
                Text("Vendor contains")
            } footer: {
                Text("Rules are checked from top to bottom without case sensitivity. For example, NEW NASCO RESTAURANT matches restaurant.")
            }

            Section {
                Button("Restore Default Rules", role: .destructive) {
                    confirmingReset = true
                }
            }
        }
        .navigationTitle("Vendor Rules")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    editingRule = VendorCategoryRule(keyword: "", category: "Restaurant")
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Add vendor rule")
            }
        }
        .sheet(item: $editingRule) { rule in
            VendorRuleEditorView(rule: rule)
                .environmentObject(store)
        }
        .confirmationDialog(
            "Restore the default vendor rules?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Restore Defaults", role: .destructive) {
                store.resetVendorRules()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct VendorRuleEditorView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var keyword: String
    @State private var category: String
    private let id: UUID

    init(rule: VendorCategoryRule) {
        id = rule.id
        _keyword = State(initialValue: rule.keyword)
        _category = State(initialValue: rule.category)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("When vendor contains") {
                    TextField("Example: restaurant", text: $keyword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Use category") {
                    Picker("Category", selection: $category) {
                        ForEach(LedgerTransaction.expenseCategories, id: \.self) { item in
                            Label(item, systemImage: AppTheme.categoryIcon(item)).tag(item)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }
            .navigationTitle("Vendor Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.saveVendorRule(
                            VendorCategoryRule(
                                id: id,
                                keyword: cleanedKeyword,
                                category: category
                            )
                        )
                        dismiss()
                    }
                    .disabled(cleanedKeyword.isEmpty)
                }
            }
        }
    }

    private var cleanedKeyword: String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
