#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

store_path = ROOT / "DailyLedger/Services/LedgerStore.swift"
store_text = store_path.read_text(encoding="utf-8")

old_collection = "return (defaults + used).compactMap { item in"
new_collection = "return (defaults + Array(used)).compactMap { item in"
if old_collection in store_text:
    store_text = store_text.replace(old_collection, new_collection, 1)
    print("Fixed cached category collection conversion.")
elif new_collection in store_text:
    print("Cached category collection conversion already fixed.")
else:
    raise RuntimeError("Expected cached category block was not found.")

old_loan_result = '''        let result = Set(increases.keys).union(decreases.keys).compactMap { currency in
            let net = increases[currency, default: 0] - decreases[currency, default: 0]
            guard net != 0 else { return nil }
            return LoanNetMovement(currencyCode: currency, netAmount: net)
        }.sorted { $0.currencyCode < $1.currencyCode }
'''
new_loan_result = '''        let currencies = Set<String>(increases.keys).union(Set<String>(decreases.keys))
        let result: [LoanNetMovement] = currencies.compactMap { currency -> LoanNetMovement? in
            let net = increases[currency, default: 0] - decreases[currency, default: 0]
            guard net != 0 else { return nil }
            return LoanNetMovement(currencyCode: currency, netAmount: net)
        }.sorted { $0.currencyCode < $1.currencyCode }
'''
if old_loan_result in store_text:
    store_text = store_text.replace(old_loan_result, new_loan_result, 1)
    print("Added explicit cached loan movement types.")
elif new_loan_result in store_text:
    print("Cached loan movement types already explicit.")
else:
    raise RuntimeError("Expected cached loan result block was not found.")

store_path.write_text(store_text, encoding="utf-8")

budget_path = ROOT / "DailyLedger/Views/BudgetSettingsView.swift"
budget_text = budget_path.read_text(encoding="utf-8")
lines = budget_text.splitlines()
cleaned_lines = []
for line in lines:
    if (
        line.strip() == ".equatable()"
        and cleaned_lines
        and cleaned_lines[-1].strip() == ".equatable()"
    ):
        continue
    cleaned_lines.append(line)
cleaned_budget = "\n".join(cleaned_lines) + ("\n" if budget_text.endswith("\n") else "")
if cleaned_budget != budget_text:
    budget_path.write_text(cleaned_budget, encoding="utf-8")
    print("Removed duplicate Equatable view wrappers.")
else:
    print("Equatable view wrappers already clean.")
