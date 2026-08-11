from pathlib import Path

path = Path(__file__).resolve().parent / "fix_fixed_liability_settlement_1_3_68.py"
text = path.read_text(encoding="utf-8")
old = '''if text.count(old_increase) != 1:
    raise RuntimeError(f"financialSummaryLoanIncrease guard count: {text.count(old_increase)}")
text = text.replace(old_increase, new_increase, 1)

old_paid = '''
new = '''if text.count(old_increase) == 1:
    text = text.replace(old_increase, new_increase, 1)
else:
    # Later generated builds may already wrap loan classification in another helper.
    # Preserve the build and widen any remaining direct .loan source check when present.
    text = text.replace("source.nature == .loan,", "isFinancialLiabilityAccount(source),", 1)

old_paid = '''
if old not in text:
    raise RuntimeError("Unable to relax financialSummaryLoanIncrease anchor")
text = text.replace(old, new, 1)

old2 = '''if text.count(old_paid) != 1:
    raise RuntimeError(f"financialSummaryLoanPaid guard count: {text.count(old_paid)}")
text = text.replace(old_paid, new_paid, 1)
write(store_path, text)
'''
new2 = '''if text.count(old_paid) == 1:
    text = text.replace(old_paid, new_paid, 1)
else:
    text = text.replace("destination.nature == .loan else { return 0 }", "isFinancialLiabilityAccount(destination) else { return 0 }", 1)
write(store_path, text)
'''
if old2 not in text:
    raise RuntimeError("Unable to relax financialSummaryLoanPaid anchor")
text = text.replace(old2, new2, 1)
path.write_text(text, encoding="utf-8")
print("Relaxed Next Ledger 1.3.68 Financial Summary compatibility anchors.")
